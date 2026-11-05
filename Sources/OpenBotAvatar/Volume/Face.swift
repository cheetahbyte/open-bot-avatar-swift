import Foundation

/// Happy-eye arc for an eye of size `w` × `h` at (x, y): a quadratic between two points level with
/// the eye's lower half, through a control point above it.
private struct HappyArc {
    let start: Point
    let control: Point
    let end: Point
    let stroke: Double

    init(x: Double, y: Double, w: Double, h: Double) {
        let halfWidth = 0.72 * w, base = y + 0.1 * h
        start = Point(x: x - halfWidth, y: base)
        control = Point(x: x, y: y - 0.42 * h)
        end = Point(x: x + halfWidth, y: base)
        stroke = 0.6 * w
    }
}

/// Drawn eyes are up to this much larger than the contract's 4 × 11 pill when the body has room.
private let eyeBoost = 1.45
/// Gap every drawn eye shape keeps from the outline before the renderer enlarges it.
private let eyeBoostPad = 3.0
/// Minimum facing of the surface under an eye for it to be drawn.
private let eyeFacing = 0.22

private struct GazeRange {
    var left: Double
    var right: Double
    var up: Double
    var down: Double
}

/// The eyes as the renderer draws them on a body's host part.
struct Face: Sendable {
    private let centers: [Point]
    /// The definition's scale enlarged as far as the body allows.
    private let scale: Double
    private let gazeLimits: GazeRange
    /// Depth of each eye's plane: the highest surface under the eye and its gaze travel, plus lift.
    let planeZ: [Double]
    /// Host surface normals under each eye (left edge, center, right edge). On a curved host an eye
    /// is hidden once any of them turns away, so a flat eye never hangs past the silhouette.
    private let normals: [[SIMD3<Double>]]

    /// `hostHeight` is the front surface of the part carrying the eyes, nil on a body with no part.
    init(eyes: AvatarEyes, polys: [[Point]], hostHeight: ((Double, Double) -> Double)?) {
        var drawn = eyes
        drawn.scale = boostedEyeScale(polys, eyes)
        let scale = drawn.scale
        self.scale = scale
        gazeLimits = gazeRange(polys, drawn)

        let centers = eyeCenters(eyes)
        self.centers = centers
        let w = EyeMetrics.width * scale / 2 + EyeMetrics.gazeX * scale
        let h = EyeMetrics.height * scale / 2 + EyeMetrics.gazeY * scale
        let samples = [-1, -0.5, 0, 0.5, 1]
        planeZ = centers.map { c in
            var top = 0.0
            for fx in samples {
                for fy in samples { top = max(top, hostHeight?(c.x + fx * w, c.y + fy * h) ?? 0) }
            }
            return top + EyeMetrics.lift
        }

        func normal(_ x: Double, _ y: Double) -> SIMD3<Double> {
            guard let hostHeight else { return SIMD3(0, 0, 1) }
            let e = 0.75
            let gx = (hostHeight(x + e, y) - hostHeight(x - e, y)) / (2 * e)
            let gy = (hostHeight(x, y + e) - hostHeight(x, y - e)) / (2 * e)
            let n = hypot(hypot(gx, gy), 1)
            return SIMD3(-gx / n, -gy / n, 1 / n)
        }
        let half = EyeMetrics.width * scale / 2
        normals = centers.map { [normal($0.x - half, $0.y), normal($0.x, $0.y), normal($0.x + half, $0.y)] }
    }

    func isVisible(_ index: Int, in basis: ViewBasis) -> Bool {
        normals[index].allSatisfy { basis.facing($0) > eyeFacing }
    }

    func mark(_ index: Int, _ pose: AvatarPose) -> AvatarEyeMark {
        let w = EyeMetrics.width * scale, h = EyeMetrics.height * scale
        let dx = pose.gazeX * (pose.gazeX >= 0 ? gazeLimits.right : gazeLimits.left) * EyeMetrics.gazeX * scale
        let dy = pose.gazeY * (pose.gazeY >= 0 ? gazeLimits.down : gazeLimits.up) * EyeMetrics.gazeY * scale
        let x = centers[index].x + dx, y = centers[index].y + dy
        if pose.eyeShape == .happy {
            let arc = HappyArc(x: x, y: y, w: w, h: h)
            return .arc(
                startX: arc.start.x, startY: arc.start.y, controlX: arc.control.x, controlY: arc.control.y,
                endX: arc.end.x, endY: arc.end.y, strokeWidth: arc.stroke)
        }
        let squint = index == 0 ? pose.squintLeft : pose.squintRight
        let open = max(h * max(0.09, (1 - pose.blink) * (1 - squint * 0.4)), w * 0.55)
        let shift = (h - open) * 0.18
        return .pill(x: x - w / 2, y: y + shift - open / 2, width: w, height: open, radius: min(w, open) / 2)
    }
}

private func drawnEyeOutline(_ cx: Double, _ cy: Double, scale: Double, margin: Double) -> [Point] {
    var points = eyeOutline(cx, cy, scale: scale, margin: margin)
    let arc = HappyArc(x: cx, y: cy, w: EyeMetrics.width * scale, h: EyeMetrics.height * scale)
    let r = arc.stroke / 2 + margin
    for i in 0...8 {
        let t = Double(i) / 8, m = 1 - t
        let x = m * m * arc.start.x + 2 * m * t * arc.control.x + t * t * arc.end.x
        let y = (m * m + t * t) * arc.start.y + 2 * m * t * arc.control.y
        for k in 0..<8 {
            let a = Double(k) / 8 * .pi * 2
            points.append(Point(x: x + cos(a) * r, y: y + sin(a) * r))
        }
    }
    return points
}

private func drawnEyesFit(_ polys: [[Point]], _ eyes: AvatarEyes, dx: Double, dy: Double, margin: Double) -> Bool {
    for c in eyeCenters(eyes) {
        for p in drawnEyeOutline(c.x + dx, c.y + dy, scale: eyes.scale, margin: margin) where !isInside(polys, p.x, p.y) {
            return false
        }
    }
    return true
}

/// How far (0...1 of the gaze limits) the drawn eyes can travel each way and keep their clearance.
private func gazeRange(_ polys: [[Point]], _ eyes: AvatarEyes) -> GazeRange {
    func reach(_ ux: Double, _ uy: Double) -> Double {
        for k in [1, 0.8, 0.6, 0.4, 0.2] {
            let dx = ux * k * EyeMetrics.gazeX * eyes.scale, dy = uy * k * EyeMetrics.gazeY * eyes.scale
            if drawnEyesFit(polys, eyes, dx: dx, dy: dy, margin: EyeMetrics.clearance) { return k }
        }
        return 0
    }
    return GazeRange(left: reach(-1, 0), right: reach(1, 0), up: reach(0, -1), down: reach(0, 1))
}

/// Largest eye scale up to `eyeBoost` × the definition's whose drawn eyes keep `eyeBoostPad`.
private func boostedEyeScale(_ polys: [[Point]], _ eyes: AvatarEyes) -> Double {
    for k in [eyeBoost, 1.38, 1.3, 1.22, 1.15, 1.08] {
        var scaled = eyes
        scaled.scale = eyes.scale * k
        if drawnEyesFit(polys, scaled, dx: 0, dy: 0, margin: eyeBoostPad) { return scaled.scale }
    }
    return eyes.scale
}
