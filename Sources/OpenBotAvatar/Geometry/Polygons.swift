import Foundation

struct Point: Hashable, Sendable {
    var x: Double
    var y: Double
}

struct Bounds: Hashable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var center: Point { Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }
}

/// Flattens into closed polygons, one per subpath.
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
    for poly in polys {
        var j = poly.count - 1
        for i in poly.indices {
            let pi = poly[i], pj = poly[j]
            if pj.y <= y {
                if pi.y > y && (pi.x - pj.x) * (y - pj.y) - (x - pj.x) * (pi.y - pj.y) > 0 { winding += 1 }
            } else if pi.y <= y && (pi.x - pj.x) * (y - pj.y) - (x - pj.x) * (pi.y - pj.y) < 0 {
                winding -= 1
            }
            j = i
        }
    }
    return winding != 0
}

/// Nonzero inside flags for many points on one row (`xs` ascending), from one pass over the edges.
func insideRow(_ polys: [[Point]], y: Double, xs: [Double], out: inout [UInt8]) {
    var hits: [(x: Double, direction: Int)] = []
    for poly in polys {
        var j = poly.count - 1
        for i in poly.indices {
            let pj = poly[j], pi = poly[i]
            if pj.y <= y && pi.y > y {
                hits.append((pj.x + (y - pj.y) * (pi.x - pj.x) / (pi.y - pj.y), 1))
            } else if pi.y <= y && pj.y > y {
                hits.append((pj.x + (y - pj.y) * (pi.x - pj.x) / (pi.y - pj.y), -1))
            }
            j = i
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

func polygonBounds(_ polys: [[Point]]) -> Bounds {
    var b = Bounds(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)
    for poly in polys {
        for p in poly {
            if p.x < b.minX { b.minX = p.x }
            if p.y < b.minY { b.minY = p.y }
            if p.x > b.maxX { b.maxX = p.x }
            if p.y > b.maxY { b.maxY = p.y }
        }
    }
    return b
}

/// Filled area estimated on a 1-unit sample grid (nonzero rule).
func filledArea(_ polys: [[Point]], _ b: Bounds) -> Double {
    var count = 0
    var xs: [Double] = []
    var x = b.minX.rounded(.down) + 0.5
    while x < b.maxX {
        xs.append(x)
        x += 1
    }
    var row = [UInt8](repeating: 0, count: xs.count)
    var y = b.minY.rounded(.down) + 0.5
    while y < b.maxY {
        insideRow(polys, y: y, xs: xs, out: &row)
        for v in row { count += Int(v) }
        y += 1
    }
    return Double(count)
}
