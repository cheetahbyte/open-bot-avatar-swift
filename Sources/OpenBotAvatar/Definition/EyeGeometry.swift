import Foundation

/// Neutral eye size and gaze limits at scale 1, viewBox units. Travel is deliberately small: a
/// subtle shift reads as looking around and keeps the enlarged eyes inside the face.
enum EyeMetrics {
    static let width = 4.0
    static let height = 11.0
    static let gazeX = 1.5
    static let gazeY = 1.1
    /// Gap the renderer keeps between every drawn eye shape and the outline while looking around.
    static let clearance = 1.5
    static let margin = 1.2
    /// Eyes sit this far above the surface so they never touch the body planes.
    static let lift = 1.5
}

func eyeCenters(_ eyes: AvatarEyes) -> [Point] {
    [Point(x: eyes.x - eyes.spacing / 2, y: eyes.y), Point(x: eyes.x + eyes.spacing / 2, y: eyes.y)]
}

func eyeOutline(_ cx: Double, _ cy: Double, scale: Double, margin: Double) -> [Point] {
    let hw = EyeMetrics.width * scale / 2 + margin
    let hh = EyeMetrics.height * scale / 2 + margin
    let straight = hh - hw
    var points: [Point] = []
    points.reserveCapacity(23)
    for k in 0..<16 {
        let a = Double(k) / 16 * .pi * 2
        let s = sin(a)
        let sign: Double = s > 0 ? 1 : s < 0 ? -1 : 0
        points.append(Point(x: cx + cos(a) * hw, y: cy + s * hw + sign * max(0, straight)))
    }
    for f in [-0.5, 0, 0.5] {
        points.append(Point(x: cx - hw, y: cy + f * straight))
        points.append(Point(x: cx + hw, y: cy + f * straight))
    }
    points.append(Point(x: cx, y: cy))
    return points
}

func eyesMiss(_ polys: [[Point]], _ eyes: AvatarEyes) -> Point? {
    for c in eyeCenters(eyes) {
        for p in eyeOutline(c.x, c.y, scale: eyes.scale, margin: EyeMetrics.margin) where !isInside(polys, p.x, p.y) {
            return p
        }
    }
    return nil
}
