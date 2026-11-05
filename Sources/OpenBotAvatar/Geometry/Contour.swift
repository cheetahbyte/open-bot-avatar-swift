/// A sampled scalar field. The outermost ring should be below every level.
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
    // Edge keys: horizontal (i,j)-(i+1,j) is 2*(j*nx+i), vertical (i,j)-(i,j+1) is that plus 1.
    // A cell links an edge once, and an edge borders two cells, so two link slots are enough.
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
                // Diagonal corners: the center decides whether they connect through the cell.
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
    let length = (dx * dx + dy * dy).squareRoot()
    if length == 0 { return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot() }
    return abs(dx * (a.y - p.y) - dy * (a.x - p.x)) / length
}

/// Ramer-Douglas-Peucker on a closed loop.
func simplifyLoop(_ loop: [Point], tolerance: Double) -> [Point] {
    if loop.count <= 8 { return loop }
    // Split at the point farthest from the first so the closed loop becomes two open chains.
    var far = 0, best = -1.0
    for k in 1..<loop.count {
        let dx = loop[k].x - loop[0].x, dy = loop[k].y - loop[0].y
        let d = (dx * dx + dy * dy).squareRoot()
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

func loopsToPath(_ loops: [[Point]]) -> String {
    var out = ""
    for loop in loops {
        out += "M\(rounded1(loop[0].x)) \(rounded1(loop[0].y))L"
        for k in 1..<loop.count {
            if k > 1 { out += " " }
            out += "\(rounded1(loop[k].x)) \(rounded1(loop[k].y))"
        }
        out += "Z"
    }
    return out
}

func loopsToSegments(_ loops: [[Point]]) -> [AvatarPathSegment] {
    var out: [AvatarPathSegment] = []
    for loop in loops {
        out.append(.move(x: loop[0].x, y: loop[0].y))
        for p in loop.dropFirst() { out.append(.line(x: p.x, y: p.y)) }
        out.append(.close)
    }
    return out
}
