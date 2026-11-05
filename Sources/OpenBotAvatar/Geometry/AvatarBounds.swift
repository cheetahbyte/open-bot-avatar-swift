/// Width and height of the box definitions are drawn in.
package let viewBoxSize = 100.0

public struct AvatarBox: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
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

extension AvatarBounds {
    var width: Double { x1 - x0 }
    var height: Double { y1 - y0 }
    var center: Point { Point(x: (x0 + x1) / 2, y: (y0 + y1) / 2) }
    var box: AvatarBox { AvatarBox(x: x0, y: y0, width: width, height: height) }
}
