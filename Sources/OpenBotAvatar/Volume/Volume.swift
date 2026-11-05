import Foundation

/// Implied volume for a flat silhouette. Every filled subpath becomes a part with a front-surface
/// height field h(x, y), mirrored about z = 0:
///
/// - inflate: a rounded slab with an elliptical edge fillet, so sides curve and the face is flat.
/// - revolve-y: a solid of revolution about the part's vertical center line (mug body, bulb).
/// - revolve-x: a solid of revolution about a horizontal axis shared by the body (barbell).
///
/// The part is then cut once into two stacks of plain cross-sections: z-slices facing the viewer and
/// x-slices facing sideways. In one flat color the union of a stack is the solid's silhouette, and
/// the renderer shows whichever stack faces the viewer more, so no plane is ever seen edge-on.
enum PartKind {
    case inflate, revolveX, revolveY
}

enum SliceAxis: Sendable {
    case z, x
}

struct VolumeSlice: Sendable {
    /// `.z` is the plane z = at, path in (x, y). `.x` is the plane x = at, path in (u = -z, y).
    var axis: SliceAxis
    var at: Double
    var d: String
    var segments: [AvatarPathSegment]
    /// Contour paths use evenodd; the core slice reuses the original nonzero outline.
    var evenOdd: Bool
    var box: AvatarBox
    /// z-slices: smallest distance from this cross-section to the outline (0 for the core and walls).
    var inset: Double
    /// Index of its entry in `PreparedAvatar.paths`.
    var pathIndex = 0
}

struct VolumePart: Sendable {
    var center: Point
    /// Front-to-back extent, centered on z = 0.
    var depth: Double
    var zSlices: [VolumeSlice]
    var xSlices: [VolumeSlice]
}

struct Volume: Sendable {
    var parts: [VolumePart]
    var bounds: Bounds
    /// The part carrying the eyes.
    var eyePart: Int
    /// Depth of each eye's plane: the highest surface under the eye and its gaze travel.
    var eyeZ: [Double]
    /// The definition's scale enlarged as far as the body allows.
    var eyeScale: Double
    /// Host surface normals under each eye (left edge, center, right edge). On a curved host an eye
    /// is hidden once any of them turns away, so a flat eye never hangs past the silhouette.
    var eyeNormals: [[SIMD3<Double>]]
}

private let maxPartDepth = 30.0
/// Drawn eyes are up to this much larger than the contract's 4 × 11 pill when the body has room.
private let eyeBoost = 1.45
/// Gap every drawn eye shape keeps from the outline before the renderer enlarges it.
private let eyeBoostPad = 3.0
private let maxXSlices = 40.0
/// Depth spacing of refinement slices, units.
private let fineZ = 0.6

private func surfaceZ(depth: Double, rxy: Double, rz: Double, distance: Double) -> Double {
    let half = depth / 2
    if rxy <= 0 || distance >= rxy { return half }
    let k = 1 - max(0, distance) / rxy
    return half - rz + max(0, 1 - k * k).squareRoot() * rz
}

/// As deep as the part is thick, but tall slender parts get up to 2.4× so they read as discs.
private func partDepth(thickness: Double, _ b: Bounds, volume: Double) -> Double {
    let long = max(b.width, b.height)
    let raw = 0.8 * max(thickness, min(0.4 * long, 2.4 * thickness))
    return min(maxPartDepth, max(3, raw)) * volume
}

private func crossings(_ polys: [[Point]], rows: Bool, at s: Double) -> [Double] {
    var out: [Double] = []
    for poly in polys {
        var j = poly.count - 1
        for i in poly.indices {
            let p = poly[j], q = poly[i]
            let (pa, pb, qa, qb) = rows ? (p.y, p.x, q.y, q.x) : (p.x, p.y, q.x, q.y)
            if (pa <= s && qa > s) || (qa <= s && pa > s) { out.append(pb + (s - pa) * (qb - pb) / (qa - pa)) }
            j = i
        }
    }
    return out.sorted()
}

private struct Profile {
    var start: Double
    var step: Double
    var radii: [Double]

    func radius(at s: Double) -> Double {
        let t = (s - start) / step
        if t < 0 || t > Double(radii.count - 1) { return 0 }
        let k = min(radii.count - 2, Int(t.rounded(.down)))
        return radii[k] + (radii[k + 1] - radii[k]) * (t - Double(k))
    }
}

/// Half-widths about `center` if every line crosses the part as one interval centered on it;
/// otherwise nil (not a solid of revolution).
private func revolveProfile(_ polys: [[Point]], rows: Bool, low: Double, high: Double, center: Double) -> Profile? {
    let step = 0.2
    let n = max(2, Int(((high - low) / step).rounded(.up)) + 1)
    var radii = [Double](repeating: 0, count: n)
    var span = 0.0
    var mids: [Double] = []
    for k in 0..<n {
        let s = min(high - 0.01, max(low + 0.01, low + Double(k) * step))
        let xs = crossings(polys, rows: rows, at: s)
        if xs.isEmpty { continue }
        if xs.count != 2 { return nil }
        radii[k] = (xs[1] - xs[0]) / 2
        span = max(span, xs[1] - xs[0])
        mids.append((xs[0] + xs[1]) / 2)
    }
    let tolerance = max(0.8, 0.04 * span)
    if mids.isEmpty || mids.contains(where: { abs($0 - center) > tolerance }) { return nil }
    return Profile(start: low, step: step, radii: radii)
}

/// Horizontal axis of revolution, if the body looks like a turned object seen from the side: at
/// least two parts, wider than tall, mirror-symmetric about y = axis and every part centered on it.
private func revolveAxis(_ body: BodyAnalysis) -> Double? {
    let b = body.bounds
    let outlines = body.subpaths.filter { !$0.hole }
    if outlines.count < 2 || b.width < 1.1 * b.height { return nil }
    let axis = (b.minY + b.maxY) / 2
    for outline in outlines {
        let ob = polygonBounds(outline.polys)
        if abs((ob.minY + ob.maxY) / 2 - axis) > 1.5 { return nil }
    }
    var filled = 0, off = 0
    var xs: [Double] = []
    var x = b.minX + 0.5
    while x < b.maxX {
        xs.append(x)
        x += 1
    }
    var top = [UInt8](repeating: 0, count: xs.count), bottom = top
    var y = b.minY + 0.5
    while y < axis {
        insideRow(body.polys, y: y, xs: xs, out: &top)
        insideRow(body.polys, y: 2 * axis - y, xs: xs, out: &bottom)
        for k in xs.indices {
            if top[k] != 0 || bottom[k] != 0 { filled += 1 }
            if top[k] != bottom[k] { off += 1 }
        }
        y += 1
    }
    return filled > 0 && Double(off) / Double(filled) < 0.02 ? axis : nil
}

private func box(of loops: [[Point]]) -> AvatarBox {
    let b = polygonBounds(loops)
    return AvatarBox(x: b.minX, y: b.minY, width: b.width, height: b.height)
}

/// Depth levels in (flat, flat + round): even in angle over the rounded part of the profile.
private func depthLevels(flat: Double, round: Double, steps: Int) -> [Double] {
    guard steps > 1 else { return [] }
    return (1..<steps).map { flat + round * sin(Double($0) / Double(steps) * (.pi / 2)) }
}

private typealias HeightField = (_ x: Double, _ y: Double) -> Double

/// Builds the implied volume. `volume` scales every depth (0 is flat).
func buildVolume(_ definition: AvatarDefinition, volume: Double, body: BodyAnalysis) -> Volume {
    let outlines = body.subpaths.filter { !$0.hole }
    let holes = body.subpaths.filter(\.hole)
    let v = volume.isFinite ? max(0, volume) : 1
    let xAxis = revolveAxis(body)
    var parts: [VolumePart] = []
    var heights: [HeightField] = []

    for outline in outlines {
        let cuts = holes.filter { hole in hole.probe.map { isInside(outline.polys, $0.x, $0.y) } ?? false }
        let polys = outline.polys + cuts.flatMap(\.polys)
        let b = polygonBounds(outline.polys)
        let center = b.center
        let step = max(0.25, min(0.45, min(b.width, b.height) / 24))

        // Shared horizontal axis, own vertical axis (multi-part bodies only), or inflated.
        var kind = PartKind.inflate
        var profile: Profile?
        if let xAxis {
            profile = revolveProfile(polys, rows: false, low: b.minX, high: b.maxX, center: xAxis)
            if profile != nil { kind = .revolveX }
        } else if outlines.count > 1 && cuts.isEmpty {
            profile = revolveProfile(polys, rows: true, low: b.minY, high: b.maxY, center: center.x)
            if profile != nil { kind = .revolveY }
        }

        let depth: Double
        var rz = 0.0
        let heightOf: (Double, Double, Double) -> Double
        if kind != .inflate, let profile {
            let axis = kind == .revolveX ? xAxis ?? 0 : center.x
            let radius = profile.radii.max() ?? 0
            depth = 2 * radius * v
            heightOf = kind == .revolveX
                ? { x, y, _ in
                    let r = profile.radius(at: x)
                    return v * max(0, r * r - (y - axis) * (y - axis)).squareRoot()
                }
                : { x, y, _ in
                    let r = profile.radius(at: y)
                    return v * max(0, r * r - (x - axis) * (x - axis)).squareRoot()
                }
        } else {
            let coarse = DepthGrid(polys, b, step: max(step, 0.6)) { _, _, _ in 0 }
            let thickness = 2 * (coarse.signedDistance.max() ?? 0).clampedAboveZero
            depth = partDepth(thickness: thickness, b, volume: v)
            let rxy = min(thickness / 2, depth / 2) * 0.9
            rz = depth / 2 * 0.85
            let (shapeDepth, shapeRz) = (depth, rz)
            heightOf = { _, _, sd in surfaceZ(depth: shapeDepth, rxy: rxy, rz: shapeRz, distance: sd) }
        }
        let inflated = kind == .inflate
        heights.append { x, y in
            isInside(polys, x, y) ? heightOf(x, y, inflated ? edgeDistance(polys, x, y) : 0) : 0
        }

        let coreD = outline.d + cuts.map(\.d).joined()
        let core = VolumeSlice(
            axis: .z, at: 0, d: coreD, segments: outline.segments + cuts.flatMap(\.segments), evenOdd: false,
            box: AvatarBox(x: b.minX, y: b.minY, width: b.width, height: b.height), inset: 0)
        var zSlices = [core]
        var xSlices: [VolumeSlice] = []
        let half = depth / 2
        if half > 0.05 {
            let g = DepthGrid(polys, b, step: step, height: heightOf)
            let steps = inflated
                ? max(4, min(14, Int(roundHalfUp(rz / 0.8))))
                : max(5, min(18, Int(roundHalfUp(half / 1.1))))
            // Inflated parts keep a straight wall up to half - rz; one slice at its end carries it.
            let levels = inflated
                ? [half - rz] + depthLevels(flat: half - rz, round: rz, steps: steps)
                : depthLevels(flat: 0, round: half, steps: steps)

            func addLevel(_ level: Double, box cellBox: CellBox? = nil) -> Bool {
                let loops = levelLoops(g, level: level, box: cellBox)
                if loops.isEmpty { return false }
                var inset = Double.infinity
                var k = 0
                for loop in loops {
                    for p in loop {
                        if k % 3 == 0 { inset = min(inset, edgeDistance(polys, p.x, p.y)) }
                        k += 1
                    }
                }
                let slice = VolumeSlice(
                    axis: .z, at: level, d: loopsToPath(loops), segments: loopsToSegments(loops), evenOdd: true,
                    box: box(of: loops), inset: inset)
                var mirror = slice
                mirror.at = -level
                zSlices.append(slice)
                zSlices.append(mirror)
                return true
            }

            var used = [0.0]
            for level in levels where level >= 0.02 && addLevel(level) { used.append(level) }
            // Thin parts of an inflated outline (deep, narrow fins): more cross-sections between the
            // levels, each clipped to its box. Revolved parts' slices span their thin side.
            for thin in inflated ? thinBoxes(g) : [] {
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
            zSlices = zSlices.enumerated()
                .sorted { $0.element.at != $1.element.at ? $0.element.at < $1.element.at : $0.offset < $1.offset }
                .map(\.element)

            // One plane per `every` grid columns, standing for the whole slab around it.
            let every = max(1, Int(roundHalfUp(max(1.1, b.width / maxXSlices) / g.step)))
            let before = (every - 1) / 2
            let edgeHeight: (Double, Double) -> Double = { x, y in heightOf(x, y, 0) }
            var i = 1
            while i < g.nx - 1 {
                let loops = columnLoops(g, c0: max(0, i - before), c1: min(g.nx - 1, i - before + every - 1), edgeHeight: edgeHeight)
                if !loops.isEmpty {
                    xSlices.append(VolumeSlice(
                        axis: .x, at: g.x0 + Double(i) * g.step, d: loopsToPath(loops), segments: loopsToSegments(loops),
                        evenOdd: true, box: box(of: loops), inset: 0))
                }
                i += every
            }
        }
        parts.append(VolumePart(center: center, depth: depth, zSlices: zSlices, xSlices: xSlices))
    }

    let eyeScale = boostedEyeScale(body, definition.eyes)
    // The eyes ride on whichever part is highest under their centers.
    let centers = eyeCenters(definition.eyes)
    var eyePart = 0, bestZ = -Double.infinity
    for (i, height) in heights.enumerated() {
        let zs = centers.map { height($0.x, $0.y) }
        if zs.contains(where: { $0 <= 0 }) { continue }
        if let z = zs.min(), z > bestZ {
            bestZ = z
            eyePart = i
        }
    }
    let host = heights.indices.contains(eyePart) ? heights[eyePart] : nil

    // Flat eye planes sit at the highest surface under the eye and its gaze travel, so the body never cuts them.
    let w = EyeMetrics.width * eyeScale / 2 + EyeMetrics.gazeX * eyeScale
    let h = EyeMetrics.height * eyeScale / 2 + EyeMetrics.gazeY * eyeScale
    let samples = [-1, -0.5, 0, 0.5, 1]
    let eyeZ = centers.map { c in
        var top = 0.0
        for fx in samples {
            for fy in samples { top = max(top, host?(c.x + fx * w, c.y + fy * h) ?? 0) }
        }
        return top
    }

    func normal(_ x: Double, _ y: Double) -> SIMD3<Double> {
        guard let host else { return SIMD3(0, 0, 1) }
        let e = 0.75
        let gx = (host(x + e, y) - host(x - e, y)) / (2 * e)
        let gy = (host(x, y + e) - host(x, y - e)) / (2 * e)
        let n = hypot(hypot(gx, gy), 1)
        return SIMD3(-gx / n, -gy / n, 1 / n)
    }
    let halfEye = EyeMetrics.width * eyeScale / 2
    let eyeNormals = centers.map { [normal($0.x - halfEye, $0.y), normal($0.x, $0.y), normal($0.x + halfEye, $0.y)] }

    return Volume(parts: parts, bounds: body.bounds, eyePart: eyePart, eyeZ: eyeZ, eyeScale: eyeScale, eyeNormals: eyeNormals)
}

/// Largest eye scale up to `eyeBoost` × the definition's whose drawn eyes keep `eyeBoostPad`.
private func boostedEyeScale(_ body: BodyAnalysis, _ eyes: AvatarEyes) -> Double {
    for k in [eyeBoost, 1.38, 1.3, 1.22, 1.15, 1.08] {
        var scaled = eyes
        scaled.scale = eyes.scale * k
        if drawnEyesFit(body.polys, scaled, dx: 0, dy: 0, margin: eyeBoostPad) { return scaled.scale }
    }
    return eyes.scale
}

private extension Double {
    /// The TS reduce starts from 0, so an all-outside grid gives 0 rather than a negative distance.
    var clampedAboveZero: Double { Swift.max(self, 0) }
}
