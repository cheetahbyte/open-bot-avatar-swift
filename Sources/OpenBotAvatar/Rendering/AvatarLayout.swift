/// A square in viewBox units.
public struct AvatarSquare: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = size
    }
}

/// An axis-aligned box in viewBox units; empty when `x0 > x1`.
public struct AvatarBounds: Hashable, Sendable {
    public var x0 = Double.infinity
    public var y0 = Double.infinity
    public var x1 = -Double.infinity
    public var y1 = -Double.infinity

    public init() {}

    public init(x0: Double, y0: Double, x1: Double, y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    mutating func add(_ p: (x: Double, y: Double)) {
        if p.x < x0 { x0 = p.x }
        if p.x > x1 { x1 = p.x }
        if p.y < y0 { y0 = p.y }
        if p.y > y1 { y1 = p.y }
    }
}

/// Sizes a bitmap to what the frames actually paint, plus slack. Covering every possible view up
/// front (`PreparedAvatar.extent`, kept as the upper bound) would cost about three times as much.
public enum AvatarBitmapFit {
    /// Slack around a frame's bounds, viewBox units: idle motion and gaze stay inside it.
    public static let slack = 8.0
    /// Margin a frame keeps from the bitmap's edge for antialiasing, viewBox units.
    public static let pad = 1.0

    /// The square to lay the bitmap out over: `previous` while it still holds `bounds`, else
    /// `previous` grown to hold it with slack. Never larger than `cap` unless `bounds` leaves `cap`.
    public static func square(previous: AvatarSquare?, bounds b: AvatarBounds, cap: AvatarSquare) -> AvatarSquare {
        guard b.x0 <= b.x1 && b.y0 <= b.y1 else { return previous ?? cap }
        if let p = previous, b.x0 - pad >= p.x, b.y0 - pad >= p.y, b.x1 + pad <= p.x + p.size, b.y1 + pad <= p.y + p.size {
            return p
        }
        var x0 = b.x0 - slack, y0 = b.y0 - slack, x1 = b.x1 + slack, y1 = b.y1 + slack
        if let p = previous {
            x0 = min(x0, p.x)
            y0 = min(y0, p.y)
            x1 = max(x1, p.x + p.size)
            y1 = max(y1, p.y + p.size)
        }
        let size = max(x1 - x0, y1 - y0)
        let insideCap = b.x0 >= cap.x && b.y0 >= cap.y && b.x1 <= cap.x + cap.size && b.y1 <= cap.y + cap.size
        if size >= cap.size && insideCap { return cap }
        return AvatarSquare(x: (x0 + x1 - size) / 2, y: (y0 + y1 - size) / 2, size: size)
    }
}

extension AvatarFrame {
    /// Each shape's matrix with `root` applied, and the bounds of everything the frame paints.
    public func placement() -> (matrices: [AvatarMatrix], bounds: AvatarBounds) {
        var bounds = AvatarBounds()
        let matrices = shapes.map { shape -> AvatarMatrix in
            let m = root.concatenating(shape.matrix)
            let box: AvatarBox
            switch shape {
            case let .slice(_, path, _): box = paths[path].box
            case let .eye(_, _, mark): box = mark.box
            }
            bounds.add(m.apply(x: box.x, y: box.y))
            bounds.add(m.apply(x: box.x + box.width, y: box.y))
            bounds.add(m.apply(x: box.x, y: box.y + box.height))
            bounds.add(m.apply(x: box.x + box.width, y: box.y + box.height))
            return m
        }
        return (matrices, bounds)
    }
}

extension AvatarEyeMark {
    fileprivate var box: AvatarBox {
        switch self {
        case let .pill(x, y, width, height, _):
            return AvatarBox(x: x, y: y, width: width, height: height)
        case let .arc(startX, startY, controlX, controlY, endX, endY, strokeWidth):
            // A quadratic arc lies within its points' hull; the stroke reaches half its width past it.
            let x = min(startX, controlX, endX) - strokeWidth, y = min(startY, controlY, endY) - strokeWidth
            return AvatarBox(
                x: x, y: y,
                width: max(startX, controlX, endX) + strokeWidth - x,
                height: max(startY, controlY, endY) + strokeWidth - y)
        }
    }
}
