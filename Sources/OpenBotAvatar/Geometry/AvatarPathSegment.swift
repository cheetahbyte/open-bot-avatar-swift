import Foundation

/// One absolute path command. `H`, `V`, `S` and `T` are normalized away when parsing.
public enum AvatarPathSegment: Hashable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case cubic(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
    case quadratic(x1: Double, y1: Double, x: Double, y: Double)
    case arc(AvatarPathArc)
    case close
}

/// An SVG endpoint arc.
public struct AvatarPathArc: Hashable, Sendable {
    public var rx: Double
    public var ry: Double
    /// Degrees.
    public var rotation: Double
    public var large: Bool
    public var sweep: Bool
    public var x: Double
    public var y: Double

    /// Center form of an arc, for drawing APIs with no endpoint arcs. Angles in radians.
    public struct Center: Sendable {
        public var x: Double
        public var y: Double
        public var rx: Double
        public var ry: Double
        public var rotation: Double
        public var start: Double
        public var delta: Double
    }

    /// Center form when drawn from (`x0`, `y0`); nil when the arc degenerates to a straight line
    /// (SVG implementation notes, F.6.5).
    public func center(fromX x0: Double, y y0: Double) -> Center? {
        if rx == 0 || ry == 0 || (x0 == x && y0 == y) { return nil }
        let phi = rotation * .pi / 180
        let cosine = cos(phi), sine = sin(phi)
        let dx = (x0 - x) / 2, dy = (y0 - y) / 2
        let x1p = cosine * dx + sine * dy, y1p = -sine * dx + cosine * dy
        var rx = abs(rx), ry = abs(ry)
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let k = lambda.squareRoot()
            rx *= k
            ry *= k
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = max(0, num / den).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = (coef * rx * y1p) / ry, cyp = (-coef * ry * x1p) / rx
        let cx = cosine * cxp - sine * cyp + (x0 + x) / 2
        let cy = sine * cxp + cosine * cyp + (y0 + y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let start = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        return Center(x: cx, y: cy, rx: rx, ry: ry, rotation: phi, start: start, delta: delta)
    }
}

func serializePath(_ segments: [AvatarPathSegment]) -> String {
    var out = ""
    let f = rounded2
    for segment in segments {
        switch segment {
        case let .move(x, y): out += "M\(f(x)) \(f(y))"
        case let .line(x, y): out += "L\(f(x)) \(f(y))"
        case let .cubic(x1, y1, x2, y2, x, y): out += "C\(f(x1)) \(f(y1)) \(f(x2)) \(f(y2)) \(f(x)) \(f(y))"
        case let .quadratic(x1, y1, x, y): out += "Q\(f(x1)) \(f(y1)) \(f(x)) \(f(y))"
        case let .arc(a):
            out += "A\(f(a.rx)) \(f(a.ry)) \(f(a.rotation)) \(a.large ? 1 : 0) \(a.sweep ? 1 : 0) \(f(a.x)) \(f(a.y))"
        case .close: out += "Z"
        }
    }
    return out
}

func splitSubpaths(_ segments: [AvatarPathSegment]) -> [[AvatarPathSegment]] {
    var out: [[AvatarPathSegment]] = []
    for segment in segments {
        if case .move = segment { out.append([]) }
        if !out.isEmpty { out[out.count - 1].append(segment) }
    }
    return out
}
