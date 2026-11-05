/// Restricted SVG path parser: M L H V C S Q T A Z, absolute and relative, and nothing else.
/// Everything downstream is rebuilt from the parsed numbers, so model-written text never reaches
/// markup.
enum PathLimits {
    static let maxCharacters = 6000
    static let maxSegments = 400
    static let maxSubpaths = 16
    static let coordinateMin = -20.0
    static let coordinateMax = 120.0
}

struct PathError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private enum Token {
    case command(Unicode.Scalar)
    case number(Double)
}

private func argumentCount(_ command: Unicode.Scalar) -> Int {
    switch command {
    case "M", "L", "T": 2
    case "H", "V": 1
    case "C": 6
    case "S", "Q": 4
    case "A": 7
    default: 0
    }
}

private func isCommand(_ s: Unicode.Scalar) -> Bool {
    "MmLlHhVvCcSsQqTtAaZz".unicodeScalars.contains(s)
}

private func isSeparator(_ s: Unicode.Scalar) -> Bool {
    s == "," || s.properties.isWhitespace || s == "\u{FEFF}"
}

private func isDigit(_ s: Unicode.Scalar) -> Bool {
    s.value >= 48 && s.value <= 57
}

private func tokenize(_ path: String) throws -> [Token] {
    let scalars = Array(path.unicodeScalars)
    if let bad = scalars.first(where: { !(isCommand($0) || isDigit($0) || isSeparator($0) || ".eE+-".unicodeScalars.contains($0)) }) {
        throw PathError("unsupported character \"\(bad)\" (allowed commands: M L H V C S Q T A Z)")
    }
    var tokens: [Token] = []
    var i = 0
    let n = scalars.count
    while i < n {
        let s = scalars[i]
        if isCommand(s) {
            tokens.append(.command(s))
            i += 1
        } else if isSeparator(s) {
            i += 1
        } else if let end = numberEnd(scalars, from: i) {
            var text = String.UnicodeScalarView()
            text.append(contentsOf: scalars[i..<end])
            tokens.append(.number(Double(String(text)) ?? .infinity))
            i = end
        } else {
            var near = String.UnicodeScalarView()
            near.append(contentsOf: scalars[i..<min(n, i + 12)])
            throw PathError("cannot parse path near \"\(String(near))\"")
        }
    }
    return tokens
}

/// End of the number at `start`: `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?`.
private func numberEnd(_ s: [Unicode.Scalar], from start: Int) -> Int? {
    var i = start
    let n = s.count
    if i < n, s[i] == "+" || s[i] == "-" { i += 1 }
    let digits = i
    while i < n, isDigit(s[i]) { i += 1 }
    let whole = i - digits
    if i < n, s[i] == "." {
        i += 1
        let fraction = i
        while i < n, isDigit(s[i]) { i += 1 }
        if whole == 0 && i == fraction { return nil }
    } else if whole == 0 {
        return nil
    }
    if i < n, s[i] == "e" || s[i] == "E" {
        var e = i + 1
        if e < n, s[e] == "+" || s[e] == "-" { e += 1 }
        let exponent = e
        while e < n, isDigit(s[e]) { e += 1 }
        if e > exponent { i = e }
    }
    return i
}

private func uppercased(_ s: Unicode.Scalar) -> Unicode.Scalar {
    s.value >= 97 ? Unicode.Scalar(s.value - 32) ?? s : s
}

/// Parses to absolute segments. Throws `PathError`.
func parsePath(_ path: String) throws -> [AvatarPathSegment] {
    if path.allSatisfy(\.isWhitespace) { throw PathError("path is empty") }
    if path.utf16.count > PathLimits.maxCharacters {
        throw PathError("path longer than \(PathLimits.maxCharacters) characters")
    }
    let tokens = try tokenize(path)
    var out: [AvatarPathSegment] = []
    var i = 0
    var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0
    var prevCubic: Point?
    var prevQuadratic: Point?
    var command: Unicode.Scalar?
    var subpaths = 0
    var open = false

    while i < tokens.count {
        if case let .command(c) = tokens[i] {
            command = c
            i += 1
            if c == "Z" || c == "z" {
                if !open { throw PathError("Z without an open subpath") }
                out.append(.close)
                cx = sx
                cy = sy
                prevCubic = nil
                prevQuadratic = nil
                open = false
                continue
            }
        } else if command == nil {
            throw PathError("path must start with M")
        } else if command == "Z" || command == "z" {
            throw PathError("numbers after Z")
        }
        guard let cmd = command else { break }
        let up = uppercased(cmd)
        let relative = cmd != up
        if out.isEmpty && up != "M" { throw PathError("path must start with M") }
        let count = argumentCount(up)
        var args: [Double] = []
        args.reserveCapacity(count)
        for k in 0..<count {
            guard i + k < tokens.count, case let .number(value) = tokens[i + k] else {
                throw PathError("command \(cmd) expects \(count) numbers")
            }
            if !value.isFinite { throw PathError("non-finite number") }
            args.append(value)
        }
        i += count
        let ox = relative ? cx : 0, oy = relative ? cy : 0
        var nextCubic: Point?
        var nextQuadratic: Point?
        switch up {
        case "M":
            if open { out.append(.close) }
            cx = args[0] + ox
            cy = args[1] + oy
            sx = cx
            sy = cy
            out.append(.move(x: cx, y: cy))
            subpaths += 1
            open = true
            command = relative ? "l" : "L"
        case "L":
            cx = args[0] + ox
            cy = args[1] + oy
            out.append(.line(x: cx, y: cy))
        case "H":
            cx = args[0] + ox
            out.append(.line(x: cx, y: cy))
        case "V":
            cy = args[0] + oy
            out.append(.line(x: cx, y: cy))
        case "C", "S":
            var x1 = cx, y1 = cy, rest = args[...]
            if up == "C" {
                x1 = args[0] + ox
                y1 = args[1] + oy
                rest = args[2...]
            } else if let previous = prevCubic {
                x1 = 2 * cx - previous.x
                y1 = 2 * cy - previous.y
            }
            let a = Array(rest)
            let x2 = a[0] + ox, y2 = a[1] + oy, x = a[2] + ox, y = a[3] + oy
            out.append(.cubic(x1: x1, y1: y1, x2: x2, y2: y2, x: x, y: y))
            nextCubic = Point(x: x2, y: y2)
            cx = x
            cy = y
        case "Q":
            let x1 = args[0] + ox, y1 = args[1] + oy, x = args[2] + ox, y = args[3] + oy
            out.append(.quadratic(x1: x1, y1: y1, x: x, y: y))
            nextQuadratic = Point(x: x1, y: y1)
            cx = x
            cy = y
        case "T":
            let x1 = prevQuadratic.map { 2 * cx - $0.x } ?? cx
            let y1 = prevQuadratic.map { 2 * cy - $0.y } ?? cy
            let x = args[0] + ox, y = args[1] + oy
            out.append(.quadratic(x1: x1, y1: y1, x: x, y: y))
            nextQuadratic = Point(x: x1, y: y1)
            cx = x
            cy = y
        case "A":
            if args[0] < 0 || args[1] < 0 { throw PathError("arc radii must be non-negative") }
            if (args[3] != 0 && args[3] != 1) || (args[4] != 0 && args[4] != 1) {
                throw PathError("arc flags must be 0 or 1, written as separate numbers")
            }
            cx = args[5] + ox
            cy = args[6] + oy
            out.append(.arc(AvatarPathArc(rx: args[0], ry: args[1], rotation: args[2], large: args[3] == 1, sweep: args[4] == 1, x: cx, y: cy)))
        default:
            throw PathError("unsupported command \(cmd)")
        }
        prevCubic = nextCubic
        prevQuadratic = nextQuadratic
        if out.count > PathLimits.maxSegments { throw PathError("more than \(PathLimits.maxSegments) segments") }
    }
    if open { out.append(.close) }
    if subpaths > PathLimits.maxSubpaths { throw PathError("more than \(PathLimits.maxSubpaths) subpaths") }
    for segment in out {
        for value in coordinates(of: segment) where value < PathLimits.coordinateMin || value > PathLimits.coordinateMax {
            throw PathError("coordinate \(numberText(value)) far outside the 0..100 viewBox")
        }
    }
    return out
}

private func coordinates(of segment: AvatarPathSegment) -> [Double] {
    switch segment {
    case let .move(x, y), let .line(x, y): [x, y]
    case let .cubic(x1, y1, x2, y2, x, y): [x1, y1, x2, y2, x, y]
    case let .quadratic(x1, y1, x, y): [x1, y1, x, y]
    case let .arc(a): [a.rx, a.ry, a.x, a.y]
    case .close: []
    }
}
