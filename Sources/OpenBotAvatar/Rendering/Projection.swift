import Foundation

/// A 2D affine matrix in SVG order (a b c d e f); same layout as `CGAffineTransform`.
public struct AvatarMatrix: Hashable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var e: Double
    public var f: Double

    public init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
    }

    static func translation(_ x: Double, _ y: Double) -> AvatarMatrix {
        AvatarMatrix(a: 1, b: 0, c: 0, d: 1, e: x, f: y)
    }

    /// `self` applied after `n`.
    public func concatenating(_ n: AvatarMatrix) -> AvatarMatrix {
        AvatarMatrix(
            a: a * n.a + c * n.b, b: b * n.a + d * n.b,
            c: a * n.c + c * n.d, d: b * n.c + d * n.d,
            e: a * n.e + c * n.f + e, f: b * n.e + d * n.f + f)
    }

    func about(_ x: Double, _ y: Double) -> AvatarMatrix {
        AvatarMatrix.translation(x, y).concatenating(self).concatenating(.translation(-x, -y))
    }

    /// Transforms a point.
    public func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + e, b * x + d * y + f)
    }
}

/// Orthographic view from yaw and pitch.
struct ViewBasis {
    private let cosYaw: Double
    private let sinYaw: Double
    private let cosPitch: Double
    private let sinPitch: Double
    /// Screen shift per unit of depth.
    private let sweep: Double
    /// Smallest on-screen size of an in-plane distance.
    private let insetScale: Double

    init(yaw: Double, pitch: Double) {
        cosYaw = cos(yaw)
        sinYaw = sin(yaw)
        cosPitch = cos(pitch)
        sinPitch = sin(pitch)
        sweep = hypot(sinYaw, cosYaw * sinPitch)
        insetScale = min(abs(cosYaw), abs(cosPitch))
    }

    /// Whether a z-slice `inset` from the outline stays behind the core at depth `z`.
    func hides(inset: Double, z: Double) -> Bool {
        inset > 0 && abs(z) * sweep <= inset * insetScale
    }

    /// Toward-viewer component of a model-space direction (1 is straight at the viewer).
    func facing(_ n: SIMD3<Double>) -> Double {
        sinPitch * n.y + cosPitch * (-sinYaw * n.x + cosYaw * n.z)
    }

    /// Whether the x-slices face the viewer more than the z-slices.
    var showsSide: Bool {
        abs(cosYaw) < abs(sinYaw)
    }

    /// Projection of the plane at depth z, pivoting on `pivot` at z = 0.
    func plane(z: Double, pivot: Point) -> AvatarMatrix {
        AvatarMatrix(
            a: cosYaw, b: sinYaw * sinPitch, c: 0, d: cosPitch,
            e: pivot.x - cosYaw * pivot.x + sinYaw * z,
            f: pivot.y - cosPitch * pivot.y - sinYaw * sinPitch * pivot.x - cosYaw * sinPitch * z)
    }

    /// Projection of the side plane x = x0, whose local coordinates are (u = -z, y).
    func sidePlane(x0: Double, pivot: Point) -> AvatarMatrix {
        AvatarMatrix(
            a: -sinYaw, b: cosYaw * sinPitch, c: 0, d: cosPitch,
            e: pivot.x + cosYaw * (x0 - pivot.x),
            f: pivot.y - cosPitch * pivot.y + sinYaw * sinPitch * (x0 - pivot.x))
    }

    /// Depth toward the viewer of a 3D point.
    func depth(x: Double, y: Double, z: Double, pivot: Point) -> Double {
        facing(SIMD3(x - pivot.x, y - pivot.y, z))
    }
}
