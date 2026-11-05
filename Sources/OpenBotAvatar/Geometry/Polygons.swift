import Foundation

struct Point: Hashable, Sendable {
    var x: Double
    var y: Double
}

@inline(__always)
func forEachEdge(_ polys: [[Point]], _ body: (Point, Point) -> Void) {
    for poly in polys {
        guard var previous = poly.last else { continue }
        for point in poly {
            body(previous, point)
            previous = point
        }
    }
}

func flattenPath(_ segments: [AvatarPathSegment]) -> [[Point]] {
    var polys: [[Point]] = []
    var current: [Point] = []
    var px = 0.0, py = 0.0
    for segment in segments {
        switch segment {
        case let .move(x, y):
            if !current.isEmpty { polys.append(current) }
            current = [Point(x: x, y: y)]
            px = x
            py = y
        case let .line(x, y):
            current.append(Point(x: x, y: y))
            px = x
            py = y
        case let .cubic(x1, y1, x2, y2, x, y):
            for k in 1...12 {
                let t = Double(k) / 12, u = 1 - t
                current.append(Point(
                    x: u * u * u * px + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x,
                    y: u * u * u * py + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y))
            }
            px = x
            py = y
        case let .quadratic(x1, y1, x, y):
            for k in 1...8 {
                let t = Double(k) / 8, u = 1 - t
                current.append(Point(x: u * u * px + 2 * u * t * x1 + t * t * x, y: u * u * py + 2 * u * t * y1 + t * t * y))
            }
            px = x
            py = y
        case let .arc(arc):
            sampleArc(arc, fromX: px, y: py, into: &current)
            px = arc.x
            py = arc.y
        case .close:
            if let first = current.first {
                polys.append(current)
                px = first.x
                py = first.y
            }
            current = []
        }
    }
    if !current.isEmpty { polys.append(current) }
    return polys.filter { $0.count >= 3 }
}

private func sampleArc(_ arc: AvatarPathArc, fromX x0: Double, y y0: Double, into out: inout [Point]) {
    guard let c = arc.center(fromX: x0, y: y0) else {
        out.append(Point(x: arc.x, y: arc.y))
        return
    }
    let cosine = cos(c.rotation), sine = sin(c.rotation)
    let steps = max(4, Int((abs(c.delta) / (.pi / 2) * 6).rounded(.up)))
    for k in 1...steps {
        let t = c.start + c.delta * Double(k) / Double(steps)
        let ex = c.rx * cos(t), ey = c.ry * sin(t)
        out.append(Point(x: cosine * ex - sine * ey + c.x, y: sine * ex + cosine * ey + c.y))
    }
}

/// Nonzero winding of a point against all subpaths (the SVG default fill rule).
func isInside(_ polys: [[Point]], _ x: Double, _ y: Double) -> Bool {
    var winding = 0
    forEachEdge(polys) { p, q in
        if p.y <= y {
            if q.y > y && (q.x - p.x) * (y - p.y) - (x - p.x) * (q.y - p.y) > 0 { winding += 1 }
        } else if q.y <= y && (q.x - p.x) * (y - p.y) - (x - p.x) * (q.y - p.y) < 0 {
            winding -= 1
        }
    }
    return winding != 0
}

/// Nonzero inside flags for many points on one row (`xs` ascending), from one pass over the edges.
func insideRow(_ polys: [[Point]], y: Double, xs: [Double], out: inout [UInt8]) {
    var hits: [(x: Double, direction: Int)] = []
    forEachEdge(polys) { p, q in
        if p.y <= y && q.y > y {
            hits.append((p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y), 1))
        } else if q.y <= y && p.y > y {
            hits.append((p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y), -1))
        }
    }
    hits.sort { $0.x < $1.x }
    var winding = 0, h = 0
    for k in xs.indices {
        while h < hits.count && hits[h].x < xs[k] {
            winding += hits[h].direction
            h += 1
        }
        out[k] = winding != 0 ? 1 : 0
    }
}

func polygonBounds(_ polys: [[Point]]) -> AvatarBounds {
    var bounds = AvatarBounds()
    for poly in polys {
        for p in poly { bounds.add((p.x, p.y)) }
    }
    return bounds
}

/// Filled area estimated on a 1-unit sample grid (nonzero rule).
func filledArea(_ polys: [[Point]], _ b: AvatarBounds) -> Double {
    var count = 0
    let xs = accumulatedSamples(from: b.x0.rounded(.down) + 0.5, to: b.x1, by: 1)
    var row = [UInt8](repeating: 0, count: xs.count)
    for y in accumulatedSamples(from: b.y0.rounded(.down) + 0.5, to: b.y1, by: 1) {
        insideRow(polys, y: y, xs: xs, out: &row)
        for v in row { count += Int(v) }
    }
    return Double(count)
}
