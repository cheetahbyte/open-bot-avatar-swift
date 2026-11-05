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
}

/// Happy-eye arc as fractions of the drawn eye size: a quadratic from (x ∓ halfWidth·w, y + base·h)
/// through (x, y − peak·h), stroked `stroke`·w wide with round caps.
enum HappyArc {
    static let halfWidth = 0.72
    static let base = 0.1
    static let peak = 0.42
    static let stroke = 0.6
}

struct BodySubpath {
    var segments: [AvatarPathSegment]
    var d: String
    var polys: [[Point]]
    /// The subpath cuts a hole rather than adding fill.
    var hole: Bool
    /// A point inside the subpath's own fill (for holes: inside the cut-out).
    var probe: Point?
}

struct BodyAnalysis {
    var polys: [[Point]]
    var bounds: Bounds
    var area: Double
    var subpaths: [BodySubpath]
}

struct GazeRange: Hashable, Sendable {
    var left: Double
    var right: Double
    var up: Double
    var down: Double
}

func analyzeBody(_ path: String) throws -> BodyAnalysis {
    let segments = try parsePath(path)
    let polys = flattenPath(segments)
    let b = polygonBounds(polys)
    var subpaths: [BodySubpath] = []
    for sub in splitSubpaths(segments) {
        let own = flattenPath(sub)
        if own.isEmpty { continue }
        let ob = polygonBounds(own)
        var inside = 0.0, cut = 0.0
        var probe: Point?, cutProbe: Point?
        // Small subpaths (buttons, sockets) need a fine grid; big ones classify fine on a coarser one.
        let step = ob.width * ob.height < 900 ? 0.5 : 1.0
        let alone = own.count == polys.count
        var xs: [Double] = []
        var x = ob.minX.rounded(.down) + step / 2
        while x < ob.maxX {
            xs.append(x)
            x += step
        }
        var mine = [UInt8](repeating: 0, count: xs.count), all = mine
        var y = ob.minY.rounded(.down) + step / 2
        while y < ob.maxY {
            insideRow(own, y: y, xs: xs, out: &mine)
            if !alone { insideRow(polys, y: y, xs: xs, out: &all) }
            for k in xs.indices where mine[k] != 0 {
                inside += 1
                if probe == nil { probe = Point(x: xs[k], y: y) }
                if !alone && all[k] == 0 {
                    cut += 1
                    if cutProbe == nil { cutProbe = Point(x: xs[k], y: y) }
                }
            }
            y += step
        }
        cut *= step * step * 4
        inside *= step * step * 4
        // A subpath that is mostly empty under the full fill rule is a cut-out.
        let hole = inside > 0 && cut / inside > 0.6
        subpaths.append(BodySubpath(segments: sub, d: serializePath(sub), polys: own, hole: hole, probe: hole ? cutProbe : probe))
    }
    return BodyAnalysis(polys: polys, bounds: b, area: filledArea(polys, b), subpaths: subpaths)
}

func eyeCenters(_ eyes: AvatarEyes) -> [Point] {
    [Point(x: eyes.x - eyes.spacing / 2, y: eyes.y), Point(x: eyes.x + eyes.spacing / 2, y: eyes.y)]
}

/// Points on the outline of an eye pill expanded by `margin`.
private func eyeOutline(_ cx: Double, _ cy: Double, scale: Double, margin: Double) -> [Point] {
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

/// Outline points of every shape the renderer may draw for one eye: pill and happy arc.
private func drawnEyeOutline(_ cx: Double, _ cy: Double, scale: Double, margin: Double) -> [Point] {
    var points = eyeOutline(cx, cy, scale: scale, margin: margin)
    let w = EyeMetrics.width * scale, h = EyeMetrics.height * scale
    let x0 = cx - HappyArc.halfWidth * w, x1 = cx + HappyArc.halfWidth * w
    let yb = cy + HappyArc.base * h, yc = cy - HappyArc.peak * h
    let r = HappyArc.stroke * w / 2 + margin
    for i in 0...8 {
        let t = Double(i) / 8, m = 1 - t
        let x = m * m * x0 + 2 * m * t * cx + t * t * x1
        let y = (m * m + t * t) * yb + 2 * m * t * yc
        for k in 0..<8 {
            let a = Double(k) / 8 * .pi * 2
            points.append(Point(x: x + cos(a) * r, y: y + sin(a) * r))
        }
    }
    return points
}

/// The first eye outline point outside the body, or nil when the eyes fit.
func eyesMiss(_ polys: [[Point]], _ eyes: AvatarEyes, margin: Double) -> Point? {
    for c in eyeCenters(eyes) {
        for p in eyeOutline(c.x, c.y, scale: eyes.scale, margin: margin) where !isInside(polys, p.x, p.y) {
            return p
        }
    }
    return nil
}

/// Whether everything the renderer draws for the eyes, moved by (`dx`, `dy`), keeps `margin`.
func drawnEyesFit(_ polys: [[Point]], _ eyes: AvatarEyes, dx: Double, dy: Double, margin: Double) -> Bool {
    for c in eyeCenters(eyes) {
        for p in drawnEyeOutline(c.x + dx, c.y + dy, scale: eyes.scale, margin: margin) where !isInside(polys, p.x, p.y) {
            return false
        }
    }
    return true
}

/// How far (0...1 of the gaze limits) the drawn eyes can travel each way and keep their clearance.
func gazeRange(_ polys: [[Point]], _ eyes: AvatarEyes) -> GazeRange {
    func reach(_ ux: Double, _ uy: Double) -> Double {
        for k in [1, 0.8, 0.6, 0.4, 0.2] {
            let dx = ux * k * EyeMetrics.gazeX * eyes.scale, dy = uy * k * EyeMetrics.gazeY * eyes.scale
            if drawnEyesFit(polys, eyes, dx: dx, dy: dy, margin: EyeMetrics.clearance) { return k }
        }
        return 0
    }
    return GazeRange(left: reach(-1, 0), right: reach(1, 0), up: reach(0, -1), down: reach(0, 1))
}
