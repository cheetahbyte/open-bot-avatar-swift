import Foundation

/// One eye in its face plane, including gaze and the pill's blink/squint narrowing.
struct EyeSpot {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var open: Double
    var shift: Double
}

/// The exact pill and happy arc retain their original drawing primitives.
func plainLook(_ look: AvatarEyeLook) -> AvatarEyeShape? {
    if look.arc >= 1 { return .happy }
    return look.arc <= 0 && look.slit <= 0 ? .pill : nil
}

/// Evenly spaced points along a closed polyline, starting at its first point.
private func resampleEye(_ points: [Point], count: Int) -> [Point] {
    let n = points.count
    var at = [0.0]
    for i in 0..<n {
        let a = points[i], b = points[(i + 1) % n]
        at.append(at[i] + hypot2(b.x - a.x, b.y - a.y))
    }
    let total = at[n]
    var out: [Point] = []
    var i = 0
    for k in 0..<count {
        let s = Double(k) / Double(count) * total
        while i < n - 1 && at[i + 1] < s { i += 1 }
        let a = points[i], b = points[(i + 1) % n]
        let u = at[i + 1] > at[i] ? (s - at[i]) / (at[i + 1] - at[i]) : 0
        out.append(Point(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u))
    }
    return out
}

private func eyeSweep(_ cx: Double, _ cy: Double, _ r: Double, from: Double, to: Double, steps: Int) -> [Point] {
    (0...steps).map { i in
        let a = from + (to - from) * Double(i) / Double(steps)
        return Point(x: cx + cos(a) * r, y: cy + sin(a) * r)
    }
}

/// A stadium walked clockwise from its top centre.
private func eyePill(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double) -> [Point] {
    let r = min(w, h) / 2
    let fx = w / 2 - r, fy = h / 2 - r
    let q = Double.pi / 2
    return [Point(x: cx, y: cy - h / 2)]
        + eyeSweep(cx + fx, cy - fy, r, from: -q, to: 0, steps: 6)
        + eyeSweep(cx + fx, cy + fy, r, from: 0, to: q, steps: 6)
        + eyeSweep(cx - fx, cy + fy, r, from: q, to: 2 * q, steps: 6)
        + eyeSweep(cx - fx, cy - fy, r, from: 2 * q, to: 3 * q, steps: 6)
}

/// The happy arc's two stroke edges and round ends, clockwise from the top centre.
private func eyeArc(_ e: EyeSpot) -> [Point] {
    let hw = e.w * 0.72, base = e.y + e.h * 0.1, peak = e.y - e.h * 0.42
    let r = e.w * 0.6 / 2
    func at(_ s: Double) -> (p: Point, n: Point) {
        let m = 1 - s
        let x = e.x + hw * (2 * s - 1), y = (m * m + s * s) * base + 2 * m * s * peak
        let tx = 2 * hw, ty = 2 * (2 * s - 1) * (base - peak)
        let length = hypot2(tx, ty)
        return (Point(x: x, y: y), Point(x: ty / length, y: -tx / length))
    }
    func edge(_ from: Double, _ to: Double, _ side: Double) -> [Point] {
        (0...8).map { i in
            let (p, n) = at(from + (to - from) * Double(i) / 8)
            return Point(x: p.x + n.x * r * side, y: p.y + n.y * r * side)
        }
    }
    func end(_ s: Double) -> [Point] {
        let (p, n) = at(s)
        let up = atan2(n.y, n.x)
        return s == 1
            ? eyeSweep(p.x, p.y, r, from: up, to: up + .pi, steps: 8)
            : eyeSweep(p.x, p.y, r, from: up + .pi, to: up + 2 * .pi, steps: 8)
    }
    return edge(0.5, 1, 1) + end(1) + edge(1, 0, -1) + end(0) + edge(0, 0.5, 1)
}

/// A nearly flat capsule, both eyes tipped the same way. A blink thins it.
private func eyeSlit(_ e: EyeSpot) -> [Point] {
    let length = e.w * 1.9, thick = e.w * 0.5 * clamp(e.open / e.h, 0.3, 1)
    let c = cos(0.2), s = sin(0.2)
    return eyePill(0, 0, length, thick).map {
        Point(x: e.x + $0.x * c - $0.y * s, y: e.y + $0.x * s + $0.y * c)
    }
}

/// Forty clockwise outline points mix the pill, arc and slit at matching distances along them.
func eyeOutline(_ look: AvatarEyeLook, _ e: EyeSpot) -> [Point] {
    let a = clamp(look.arc, 0, 1), s = clamp(look.slit, 0, 1 - a)
    let shapes: [(Double, [Point])] = [
        (1 - a - s, eyePill(e.x, e.y + e.shift, e.w, e.open)),
        (a, eyeArc(e)), (s, eyeSlit(e))
    ]
    var out = Array(repeating: Point(x: 0, y: 0), count: 40)
    for (weight, shape) in shapes where weight > 0 {
        for (i, point) in resampleEye(shape, count: 40).enumerated() {
            out[i].x += point.x * weight
            out[i].y += point.y * weight
        }
    }
    return out
}

/// A smooth closed quadratic per outline point, joined at the midpoints (absolute M, Q, Z).
func outlinePath(_ points: [Point]) -> String {
    let n = points.count
    func mid(_ i: Int) -> Point {
        let a = points[i % n], b = points[(i + 1) % n]
        return Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    let start = mid(n - 1)
    var d = "M\(rounded2(start.x)) \(rounded2(start.y))"
    for i in 0..<n {
        let m = mid(i)
        d += "Q\(rounded2(points[i].x)) \(rounded2(points[i].y)) \(rounded2(m.x)) \(rounded2(m.y))"
    }
    return d + "Z"
}

func eyePath(_ look: AvatarEyeLook, _ e: EyeSpot) -> String {
    outlinePath(eyeOutline(look, e))
}
