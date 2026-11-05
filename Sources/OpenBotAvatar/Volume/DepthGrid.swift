private func segmentDistance(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    let dx = bx - ax, dy = by - ay
    let length = dx * dx + dy * dy
    var t = length > 0 ? ((px - ax) * dx + (py - ay) * dy) / length : 0
    t = t < 0 ? 0 : t > 1 ? 1 : t
    let ex = ax + t * dx - px, ey = ay + t * dy - py
    return (ex * ex + ey * ey).squareRoot()
}

func edgeDistance(_ polys: [[Point]], _ x: Double, _ y: Double) -> Double {
    var best = Double.infinity
    forEachEdge(polys) { p, q in
        best = min(best, segmentDistance(x, y, p.x, p.y, q.x, q.y))
    }
    return best
}

/// Edges bucketed on a coarse grid, for nearest-edge queries that only visit nearby buckets.
private struct EdgeIndex {
    private let cell = 3.0
    private let buckets: [[Int32]]
    private let edges: [Double]
    private let originX: Double
    private let originY: Double
    private let span: Int

    init(_ polys: [[Point]], _ b: AvatarBounds) {
        originX = b.x0 - 4
        originY = b.y0 - 4
        span = Int(((max(b.width, b.height) + 8) / cell).rounded(.up)) + 1
        var buckets = [[Int32]](repeating: [], count: span * span)
        var edges: [Double] = []
        let span = span, originX = originX, originY = originY, cell = cell
        forEachEdge(polys) { p, q in
            let k = Int32(edges.count)
            edges.append(contentsOf: [p.x, p.y, q.x, q.y])
            for cy in Self.cell(min(p.y, q.y), originY, cell, span)...Self.cell(max(p.y, q.y), originY, cell, span) {
                for cx in Self.cell(min(p.x, q.x), originX, cell, span)...Self.cell(max(p.x, q.x), originX, cell, span) {
                    buckets[cy * span + cx].append(k)
                }
            }
        }
        self.buckets = buckets
        self.edges = edges
    }

    private static func cell(_ value: Double, _ origin: Double, _ cell: Double, _ span: Int) -> Int {
        max(0, min(span - 1, Int(((value - origin) / cell).rounded(.down))))
    }

    /// Searches rings of buckets outward until no closer edge can exist.
    func distance(_ x: Double, _ y: Double) -> Double {
        let bx = Self.cell(x, originX, cell, span), by = Self.cell(y, originY, cell, span)
        var best = Double.infinity
        var r = 0
        while r < span {
            var cy = by - r
            while cy <= by + r {
                defer { cy += 1 }
                if cy < 0 || cy >= span { continue }
                let edgeRow = cy == by - r || cy == by + r
                let stride = edgeRow || r == 0 ? 1 : 2 * r
                var cx = bx - r
                while cx <= bx + r {
                    defer { cx += stride }
                    if cx < 0 || cx >= span { continue }
                    for e in buckets[cy * span + cx] {
                        let k = Int(e)
                        let d = segmentDistance(x, y, edges[k], edges[k + 1], edges[k + 2], edges[k + 3])
                        if d < best { best = d }
                    }
                }
            }
            if best <= Double(r) * cell { break }
            r += 1
        }
        return best
    }
}

/// Sampled signed distance (positive inside) and height over a part's bounds.
struct DepthGrid {
    var x0: Double
    var y0: Double
    var step: Double
    var nx: Int
    var ny: Int
    var signedDistance: [Double]
    var height: [Double]

    init(_ polys: [[Point]], _ b: AvatarBounds, step: Double, height heightAt: (Double, Double, Double) -> Double) {
        let pad = 1.0
        x0 = b.x0 - pad
        y0 = b.y0 - pad
        self.step = step
        nx = Int(((b.width + 2 * pad) / step).rounded(.up)) + 1
        ny = Int(((b.height + 2 * pad) / step).rounded(.up)) + 1
        signedDistance = Array(repeating: 0, count: nx * ny)
        height = Array(repeating: 0, count: nx * ny)
        let index = EdgeIndex(polys, b)
        let xs = (0..<nx).map { (b.x0 - pad) + Double($0) * step }
        var inside = [UInt8](repeating: 0, count: nx)
        for j in 0..<ny {
            let y = y0 + Double(j) * step
            insideRow(polys, y: y, xs: xs, out: &inside)
            for i in 0..<nx {
                let d = index.distance(xs[i], y)
                signedDistance[j * nx + i] = inside[i] != 0 ? d : -d
                height[j * nx + i] = inside[i] != 0 ? heightAt(xs[i], y, d) : 0
            }
        }
    }
}

/// A rectangle of grid samples, inclusive.
struct CellBox {
    var i0: Int
    var i1: Int
    var j0: Int
    var j1: Int
    /// Highest surface over the box's thin samples.
    var top = 0.0
}

/// How far a simplified cross-section may stray from its contour, units.
private let contourTolerance = 0.04

/// Steepness of the outline term in the contour field, so cross-sections hug the outline.
private let outlineSlope = 4.0

/// Cross-section {h ≥ level} clipped to the outline (and to `box`, if given), as loops.
func levelLoops(_ g: DepthGrid, level: Double, box: CellBox? = nil) -> [[Point]] {
    let i0 = box.map { max(0, $0.i0 - 1) } ?? 0, i1 = box.map { min(g.nx - 1, $0.i1 + 1) } ?? g.nx - 1
    let j0 = box.map { max(0, $0.j0 - 1) } ?? 0, j1 = box.map { min(g.ny - 1, $0.j1 + 1) } ?? g.ny - 1
    let nx = i1 - i0 + 1, ny = j1 - j0 + 1
    var values = [Double](repeating: 0, count: nx * ny)
    for j in 0..<ny {
        for i in 0..<nx {
            let k = (j + j0) * g.nx + i + i0
            var v = min(g.height[k] - level, outlineSlope * g.signedDistance[k])
            if let box {
                let inward = min(i + i0 - box.i0, box.i1 - i - i0, j + j0 - box.j0, box.j1 - j - j0)
                v = min(v, outlineSlope * g.step * Double(inward))
            }
            values[j * nx + i] = v
        }
    }
    let field = Field(values: values, nx: nx, ny: ny, x0: g.x0 + Double(i0) * g.step, y0: g.y0 + Double(j0) * g.step, step: g.step)
    return contourLoops(field).map { simplifyLoop($0, tolerance: contourTolerance) }.filter { $0.count >= 3 }
}

/// Thin regions get refinement slices: a thin, deep protrusion seen at an angle shifts more between
/// neighboring slices than it is wide, so without them it fans out into separate copies.
private let thinRadius = 4.0
private let thinReach = 5.0
private let thinMargin = 2.0

/// Boxes around the parts of an outline where no inscribed circle within `thinReach` has a radius of
/// `thinRadius` or more, grown by `thinMargin` and merged where they overlap.
func thinBoxes(_ g: DepthGrid) -> [CellBox] {
    let nx = g.nx, ny = g.ny
    let sd = g.signedDistance
    let reach = Int((thinReach / g.step).rounded(.up))
    var rows = [Double](repeating: 0, count: nx * ny), widest = rows
    for j in 0..<ny {
        for i in 0..<nx {
            var m = 0.0
            for k in max(0, i - reach)...min(nx - 1, i + reach) { m = max(m, sd[j * nx + k]) }
            rows[j * nx + i] = m
        }
    }
    for i in 0..<nx {
        for j in 0..<ny {
            var m = 0.0
            for k in max(0, j - reach)...min(ny - 1, j + reach) { m = max(m, rows[k * nx + i]) }
            widest[j * nx + i] = m
        }
    }
    func thin(_ k: Int) -> Bool { sd[k] > 0 && widest[k] < thinRadius }

    var seen = [Bool](repeating: false, count: nx * ny)
    let grow = Int((thinMargin / g.step).rounded(.up))
    var boxes: [CellBox] = []
    for start in 0..<(nx * ny) where !seen[start] && thin(start) {
        var box = CellBox(i0: nx, i1: -1, j0: ny, j1: -1)
        var cells = 0
        var stack = [start]
        seen[start] = true
        while let k = stack.popLast() {
            let i = k % nx, j = (k - i) / nx
            cells += 1
            box.top = max(box.top, g.height[k])
            box.i0 = min(box.i0, i)
            box.i1 = max(box.i1, i)
            box.j0 = min(box.j0, j)
            box.j1 = max(box.j1, j)
            for n in [i > 0 ? k - 1 : -1, i < nx - 1 ? k + 1 : -1, j > 0 ? k - nx : -1, j < ny - 1 ? k + nx : -1]
            where n >= 0 && !seen[n] && thin(n) {
                seen[n] = true
                stack.append(n)
            }
        }
        if Double(cells) * g.step * g.step < 2 { continue }
        boxes.append(CellBox(
            i0: max(0, box.i0 - grow), i1: min(nx - 1, box.i1 + grow),
            j0: max(0, box.j0 - grow), j1: min(ny - 1, box.j1 + grow), top: box.top))
    }
    var a = 0
    while a < boxes.count {
        var b = a + 1
        while b < boxes.count {
            let p = boxes[a], q = boxes[b]
            if p.i0 > q.i1 || q.i0 > p.i1 || p.j0 > q.j1 || q.j0 > p.j1 {
                b += 1
                continue
            }
            boxes[a] = CellBox(
                i0: min(p.i0, q.i0), i1: max(p.i1, q.i1), j0: min(p.j0, q.j0), j1: max(p.j1, q.j1), top: max(p.top, q.top))
            boxes.remove(at: b)
            b = a + 1
        }
        a += 1
    }
    return boxes
}

/// Side profile for the slab of grid columns c0...c1: loops in (u = -z, y), symmetric in u. Each row
/// takes the largest height across the slab, so a stack of these seen side-on adds up to the solid's
/// side silhouette. Where a run meets the outline the profile ends at the surface height right there.
func columnLoops(_ g: DepthGrid, c0: Int, c1: Int, edgeHeight: (Double, Double) -> Double) -> [[Point]] {
    var loops: [[Point]] = []
    var sd = [Double](repeating: -.infinity, count: g.ny)
    var h = [Double](repeating: 0, count: g.ny)
    for j in 0..<g.ny {
        for c in c0...c1 {
            let k = j * g.nx + c
            if g.signedDistance[k] > sd[j] { sd[j] = g.signedDistance[k] }
            if g.signedDistance[k] > 0 && g.height[k] > h[j] { h[j] = g.height[k] }
        }
    }
    func yAt(_ j: Int) -> Double { g.y0 + Double(j) * g.step }
    func edge(_ inside: Int, _ outside: Int) -> Double {
        yAt(inside) + (yAt(outside) - yAt(inside)) * sd[inside] / (sd[inside] - sd[outside])
    }
    func rim(_ y: Double, _ j: Int) -> Double {
        var top = 0.0
        for c in c0...c1 { top = max(top, edgeHeight(g.x0 + Double(c) * g.step, y)) }
        return min(h[j], top)
    }
    var j = 0
    while j < g.ny {
        if sd[j] <= 0 {
            j += 1
            continue
        }
        let j0 = j
        while j < g.ny && sd[j] > 0 { j += 1 }
        let j1 = j - 1
        let yTop = j0 > 0 ? edge(j0, j0 - 1) : yAt(j0)
        let yBottom = j1 < g.ny - 1 ? edge(j1, j1 + 1) : yAt(j1)
        var right = [Point(x: j0 > 0 ? rim(yTop, j0) : h[j0], y: yTop)]
        for k in j0...j1 { right.append(Point(x: h[k], y: yAt(k))) }
        right.append(Point(x: j1 < g.ny - 1 ? rim(yBottom, j1) : h[j1], y: yBottom))
        if (right.map(\.x).max() ?? 0) < 0.05 { continue }
        let left = right.reversed().map { Point(x: -$0.x, y: $0.y) }
        loops.append(simplifyLoop(right + left, tolerance: contourTolerance))
    }
    return loops
}
