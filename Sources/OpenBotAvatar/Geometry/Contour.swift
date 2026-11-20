import Foundation

/// A sampled scalar field. The outermost ring should be negative.
struct Field {
    var values: [Double]
    var nx: Int
    var ny: Int
    var x0: Double
    var y0: Double
    var step: Double
}

/// Closed loops where the field crosses zero (marching squares), assembled in first-seen order.
func contourLoops(_ field: Field) -> [[Point]] {
    let nx = field.nx, ny = field.ny, values = field.values
    let keys = 2 * nx * ny
    var firstLink = [Int32](repeating: -1, count: keys)
    var secondLink = [Int32](repeating: -1, count: keys)
    var order: [Int] = []

    func attach(_ a: Int, _ b: Int) {
        if firstLink[a] < 0 {
            firstLink[a] = Int32(b)
            order.append(a)
        } else {
            secondLink[a] = Int32(b)
        }
    }

    func link(_ p: Int, _ q: Int) {
        attach(p, q)
        attach(q, p)
    }

    func point(_ key: Int) -> Point {
        let index = key >> 1, i = index % nx, j = (index - i) / nx
        let a = values[j * nx + i]
        if key & 1 != 0 {
            let b = values[(j + 1) * nx + i], t = a / (a - b)
            return Point(x: field.x0 + Double(i) * field.step, y: field.y0 + (Double(j) + t) * field.step)
        }
        let b = values[j * nx + i + 1], t = a / (a - b)
        return Point(x: field.x0 + (Double(i) + t) * field.step, y: field.y0 + Double(j) * field.step)
    }

    for j in 0..<(ny - 1) {
        for i in 0..<(nx - 1) {
            let vtl = values[j * nx + i], vtr = values[j * nx + i + 1]
            let vbr = values[(j + 1) * nx + i + 1], vbl = values[(j + 1) * nx + i]
            let tl = vtl >= 0, tr = vtr >= 0, br = vbr >= 0, bl = vbl >= 0
            let code = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
            if code == 0 || code == 15 { continue }
            let top = 2 * (j * nx + i), bottom = 2 * ((j + 1) * nx + i)
            let left = 2 * (j * nx + i) + 1, right = 2 * (j * nx + i + 1) + 1
            if code == 10 || code == 5 {
                let center = (vtl + vtr + vbr + vbl) / 4 >= 0
                if (code == 10) == center {
                    link(top, right)
                    link(bottom, left)
                } else {
                    link(left, top)
                    link(right, bottom)
                }
                continue
            }
            var a = -1, b = -1
            func cross(_ edge: Int) {
                if a < 0 { a = edge } else { b = edge }
            }
            if tl != tr { cross(top) }
            if tr != br { cross(right) }
            if br != bl { cross(bottom) }
            if bl != tl { cross(left) }
            link(a, b)
        }
    }

    var loops: [[Point]] = []
    var seen = [Bool](repeating: false, count: keys)
    for start in order where !seen[start] {
        var loop: [Point] = []
        var previous = -1, current = start
        while !seen[current] {
            seen[current] = true
            loop.append(point(current))
            let first = Int(firstLink[current]), second = Int(secondLink[current])
            var next = -1
            if first != previous && !seen[first] {
                next = first
            } else if second >= 0 && second != previous && !seen[second] {
                next = second
            }
            if next < 0 { break }
            previous = current
            current = next
        }
        if loop.count >= 3 { loops.append(loop) }
    }
    return loops
}

private func perpendicular(_ p: Point, _ a: Point, _ b: Point) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let length = hypot2(dx, dy)
    if length == 0 { return hypot2(p.x - a.x, p.y - a.y) }
    return abs(dx * (a.y - p.y) - dy * (a.x - p.x)) / length
}

func simplifyLoop(_ loop: [Point], tolerance: Double) -> [Point] {
    if loop.count <= 8 { return loop }
    var far = 0, best = -1.0
    for k in 1..<loop.count {
        let dx = loop[k].x - loop[0].x, dy = loop[k].y - loop[0].y
        let d = hypot2(dx, dy)
        if d > best {
            best = d
            far = k
        }
    }
    var keep = [Bool](repeating: false, count: loop.count)
    keep[0] = true
    keep[far] = true
    var stack = [(0, far), (far, loop.count)]
    while let (s, e) = stack.popLast() {
        let end = loop[e % loop.count]
        var index = -1, largest = tolerance
        var k = s + 1
        while k < e {
            let d = perpendicular(loop[k], loop[s], end)
            if d > largest {
                largest = d
                index = k
            }
            k += 1
        }
        if index >= 0 {
            keep[index] = true
            stack.append((s, index))
            stack.append((index, e))
        }
    }
    var out: [Point] = []
    for k in loop.indices where keep[k] { out.append(loop[k]) }
    return out
}

/// A hundredth-unit grid coordinate as a compact SVG number, without a leading zero or `-0`.
private func contourNumber(_ k: Int) -> String {
    let a = abs(k), whole = a / 100, fraction = a % 100
    let suffix: String
    if fraction == 0 {
        suffix = ""
    } else if fraction % 10 == 0 {
        suffix = ".\(fraction / 10)"
    } else if fraction < 10 {
        suffix = ".0\(fraction)"
    } else {
        suffix = ".\(fraction)"
    }
    return (k < 0 ? "-" : "") + (whole != 0 || suffix.isEmpty ? String(whole) : "") + suffix
}

/// Smooth closed contours with sharp outline corners preserved. The compact SVG path and native
/// absolute segments share the same snapped geometry; native drawing never falls back to polylines.
func loopsToPath(_ loops: [[Point]]) -> (d: String, segments: [AvatarPathSegment]) {
    var d = "", command = "", last = ""
    var segments: [AvatarPathSegment] = []

    func emit(_ c: String, _ coordinates: Int...) {
        if c != command {
            d += c
            command = c
            last = ""
        }
        for k in coordinates {
            let text = contourNumber(k)
            if !last.isEmpty && !text.hasPrefix("-") && !(text.hasPrefix(".") && last.contains(".")) {
                d += " "
            }
            d += text
            last = text
        }
    }

    for loop in loops {
        let n = loop.count
        let vertices = loop.map { (x: 2 * Int(roundHalfUp($0.x * 100 / 2)), y: 2 * Int(roundHalfUp($0.y * 100 / 2))) }
        let corners = loop.indices.map { k in
            let p = loop[k], a = loop[(k + n - 1) % n], b = loop[(k + 1) % n]
            let cross = (p.x - a.x) * (b.y - p.y) - (p.y - a.y) * (b.x - p.x)
            let dot = (p.x - a.x) * (b.x - p.x) + (p.y - a.y) * (b.y - p.y)
            // Sharp turns, or gentle turns between long edges whose curve would sag by > 0.1.
            return abs(atan2(cross, dot)) > 0.6 || abs(cross) > 4 * 0.1 * hypot2(b.x - a.x, b.y - a.y)
        }
        func midpoint(_ k: Int) -> (x: Int, y: Int) {
            let a = vertices[k % n], b = vertices[(k + 1) % n]
            return ((a.x + b.x) / 2, (a.y + b.y) / 2)
        }
        var (cx, cy) = midpoint(0)
        emit("M", cx, cy)
        segments.append(.move(x: Double(cx) / 100, y: Double(cy) / 100))
        var smooth = false
        for k in 1...n {
            let p = vertices[k % n]
            if corners[k % n] {
                emit("l", p.x - cx, p.y - cy)
                segments.append(.line(x: Double(p.x) / 100, y: Double(p.y) / 100))
                cx = p.x
                cy = p.y
                if k < n && !corners[(k + 1) % n] {
                    let m = midpoint(k)
                    emit("l", m.x - cx, m.y - cy)
                    segments.append(.line(x: Double(m.x) / 100, y: Double(m.y) / 100))
                    cx = m.x
                    cy = m.y
                }
                smooth = false
            } else {
                let m = midpoint(k)
                if smooth {
                    emit("t", m.x - cx, m.y - cy)
                } else {
                    emit("q", p.x - cx, p.y - cy, m.x - cx, m.y - cy)
                }
                // Reflection across the shared midpoint makes this vertex the control of `t` too.
                segments.append(.quadratic(x1: Double(p.x) / 100, y1: Double(p.y) / 100, x: Double(m.x) / 100, y: Double(m.y) / 100))
                cx = m.x
                cy = m.y
                smooth = true
            }
        }
        d += "Z"
        command = "Z"
        last = ""
        segments.append(.close)
    }
    return (d, segments)
}
