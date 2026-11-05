import Foundation

/// Implied volume for a flat silhouette. Every filled subpath becomes a part with a `PartShape`,
/// which is cut once into two stacks of plain cross-sections: z-slices facing the viewer and x-slices
/// facing sideways. In one flat color the union of a stack is the solid's silhouette, and the
/// renderer shows whichever stack faces the viewer more, so no plane is ever seen edge-on.
struct Volume: Sendable {
    var parts: [VolumePart]
    /// Distinct cross-sections; slices refer to them by index.
    var outlines: [SliceOutline]
    var bounds: AvatarBounds
    /// The part carrying the eyes.
    var eyePart: Int
    var face: Face
}

struct VolumePart: Sendable {
    var center: Point
    var depth: Double
    var zSlices: [VolumeSlice]
    var xSlices: [VolumeSlice]
}

struct VolumeSlice: Sendable {
    /// The plane z = at in a z-stack, with its outline in (x, y). The plane x = at in an x-stack,
    /// with its outline in (u = -z, y).
    var at: Double
    /// z-slices: smallest distance from this cross-section to the outline (0 for the core).
    var inset: Double
    var isCore = false
    var outline: Int
}

/// One cross-section. `d` is a rounded serialization of `segments`, and identifies equal geometry.
struct SliceOutline: Sendable {
    var d: String
    var segments: [AvatarPathSegment]
    /// Contour paths use evenodd; the core slice reuses the original nonzero outline.
    var evenOdd: Bool
    var box: AvatarBox

    init(core subpaths: [BodySubpath], bounds: AvatarBounds) {
        d = subpaths.map(\.d).joined()
        segments = subpaths.flatMap(\.segments)
        evenOdd = false
        box = bounds.box
    }

    init(loops: [[Point]]) {
        var d = ""
        var segments: [AvatarPathSegment] = []
        for loop in loops {
            d += "M\(rounded1(loop[0].x)) \(rounded1(loop[0].y))L"
            segments.append(.move(x: loop[0].x, y: loop[0].y))
            for k in 1..<loop.count {
                if k > 1 { d += " " }
                d += "\(rounded1(loop[k].x)) \(rounded1(loop[k].y))"
                segments.append(.line(x: loop[k].x, y: loop[k].y))
            }
            d += "Z"
            segments.append(.close)
        }
        self.d = d
        self.segments = segments
        evenOdd = true
        box = polygonBounds(loops).box
    }
}

private let maxXSlices = 40.0
/// Depth spacing of refinement slices, units.
private let fineZ = 0.6

/// A slice before its outline is entered in the volume's table.
private struct SliceDraft {
    var at: Double
    var inset: Double
    var isCore = false
    var outline: SliceOutline
}

private struct OutlineTable {
    var outlines: [SliceOutline] = []
    private var indices: [String: Int] = [:]

    mutating func enter(_ drafts: [SliceDraft]) -> [VolumeSlice] {
        drafts.map { draft in
            let index = indices[draft.outline.d] ?? outlines.count
            if index == outlines.count {
                indices[draft.outline.d] = index
                outlines.append(draft.outline)
            }
            return VolumeSlice(at: draft.at, inset: draft.inset, isCore: draft.isCore, outline: index)
        }
    }
}

/// Builds the implied volume. `volume` scales every depth (0 is flat).
func buildVolume(eyes: AvatarEyes, volume: Double, body: BodyAnalysis) -> Volume {
    let outlines = body.subpaths.filter { !$0.isHole }
    let holes = body.subpaths.filter(\.isHole)
    let sharedAxis = sharedRevolveAxis(body)
    var table = OutlineTable()
    var parts: [VolumePart] = []
    var surfaces: [(Double, Double) -> Double] = []

    for outline in outlines {
        let cuts = holes.filter { hole in hole.cutProbe.map { isInside(outline.polys, $0.x, $0.y) } == true }
        let polys = outline.polys + cuts.flatMap(\.polys)
        let b = polygonBounds(outline.polys)
        let step = max(0.25, min(0.45, min(b.width, b.height) / 24))
        let shape = PartShape.classify(
            polys: polys, bounds: b, sharedAxis: sharedAxis, canRevolveAlone: outlines.count > 1 && cuts.isEmpty,
            gridStep: step, volume: volume)
        surfaces.append { x, y in
            isInside(polys, x, y) ? shape.height(x, y, distance: edgeDistance(polys, x, y)) : 0
        }

        var zDrafts = [SliceDraft(at: 0, inset: 0, isCore: true, outline: SliceOutline(core: [outline] + cuts, bounds: b))]
        var xDrafts: [SliceDraft] = []
        if shape.depth / 2 > 0.05 {
            let grid = DepthGrid(polys, b, step: step) { x, y, distance in shape.height(x, y, distance: distance) }
            zDrafts += faceSlices(polys, shape, grid)
            xDrafts = sideSlices(b, shape, grid)
        }
        zDrafts = zDrafts.enumerated()
            .sorted { $0.element.at != $1.element.at ? $0.element.at < $1.element.at : $0.offset < $1.offset }
            .map(\.element)
        parts.append(VolumePart(center: b.center, depth: shape.depth, zSlices: table.enter(zDrafts), xSlices: table.enter(xDrafts)))
    }

    let centers = eyeCenters(eyes)
    var eyePart = 0, bestZ = -Double.infinity
    for (i, surface) in surfaces.enumerated() {
        let zs = centers.map { surface($0.x, $0.y) }
        if zs.contains(where: { $0 <= 0 }) { continue }
        if let z = zs.min(), z > bestZ {
            bestZ = z
            eyePart = i
        }
    }
    let host = surfaces.indices.contains(eyePart) ? surfaces[eyePart] : nil
    let face = Face(eyes: eyes, polys: body.polys, hostHeight: host)
    return Volume(parts: parts, outlines: table.outlines, bounds: body.bounds, eyePart: eyePart, face: face)
}

/// Depth levels in (flat, flat + round): even in angle over the rounded part of the profile.
private func depthLevels(flat: Double, round: Double, steps: Int) -> [Double] {
    (1..<steps).map { flat + round * sin(Double($0) / Double(steps) * (.pi / 2)) }
}

/// Mirrored pairs of z-slices: the shape's level sets, and refinements over its thin regions.
private func faceSlices(_ polys: [[Point]], _ shape: PartShape, _ grid: DepthGrid) -> [SliceDraft] {
    var drafts: [SliceDraft] = []

    func addLevel(_ level: Double, box: CellBox? = nil) -> Bool {
        let loops = levelLoops(grid, level: level, box: box)
        if loops.isEmpty { return false }
        var inset = Double.infinity
        for (k, p) in loops.joined().enumerated() where k % 3 == 0 {
            inset = min(inset, edgeDistance(polys, p.x, p.y))
        }
        let outline = SliceOutline(loops: loops)
        drafts.append(SliceDraft(at: level, inset: inset, outline: outline))
        drafts.append(SliceDraft(at: -level, inset: inset, outline: outline))
        return true
    }

    let half = shape.depth / 2
    let levels: [Double]
    var refines = false
    if case let .inflated(_, _, rz) = shape {
        let steps = max(4, min(14, Int(roundHalfUp(rz / 0.8))))
        levels = [half - rz] + depthLevels(flat: half - rz, round: rz, steps: steps)
        refines = true
    } else {
        let steps = max(5, min(18, Int(roundHalfUp(half / 1.1))))
        levels = depthLevels(flat: 0, round: half, steps: steps)
    }
    var used = [0.0]
    for level in levels where level >= 0.02 && addLevel(level) { used.append(level) }

    for thin in refines ? thinBoxes(grid) : [] {
        var k = 1
        while k < used.count && used[k - 1] < thin.top {
            let a = used[k - 1], gap = used[k] - a
            let m = Int((gap / fineZ - 1e-9).rounded(.up))
            var q = 1
            while q < m && a + gap * Double(q) / Double(m) < thin.top {
                _ = addLevel(a + gap * Double(q) / Double(m), box: thin)
                q += 1
            }
            k += 1
        }
    }
    return drafts
}

/// One x-slice per `every` grid columns, standing for the whole slab around it.
private func sideSlices(_ b: AvatarBounds, _ shape: PartShape, _ grid: DepthGrid) -> [SliceDraft] {
    let every = max(1, Int(roundHalfUp(max(1.1, b.width / maxXSlices) / grid.step)))
    let before = (every - 1) / 2
    var drafts: [SliceDraft] = []
    var i = 1
    while i < grid.nx - 1 {
        let loops = columnLoops(grid, c0: max(0, i - before), c1: min(grid.nx - 1, i - before + every - 1)) { x, y in
            shape.height(x, y, distance: 0)
        }
        if !loops.isEmpty {
            drafts.append(SliceDraft(at: grid.x0 + Double(i) * grid.step, inset: 0, outline: SliceOutline(loops: loops)))
        }
        i += every
    }
    return drafts
}
