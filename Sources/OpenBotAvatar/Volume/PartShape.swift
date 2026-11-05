private let maxPartDepth = 30.0

/// A part's solid. Its front surface is mirrored about z = 0.
enum PartShape {
    /// A rounded slab: height follows an elliptical edge fillet of the distance to the outline, so
    /// sides curve and the face is flat.
    case inflated(depth: Double, rxy: Double, rz: Double)
    /// A solid of revolution about the line `axis`: a horizontal line through the whole body
    /// (barbell) or the part's own vertical center line (mug body, bulb).
    case revolved(Profile, axis: Double, horizontal: Bool, volume: Double)

    /// Front-to-back extent.
    var depth: Double {
        switch self {
        case let .inflated(depth, _, _): depth
        case let .revolved(profile, _, _, volume): 2 * (profile.radii.max() ?? 0) * volume
        }
    }

    /// Front surface at (x, y). `distance` is the inward distance to the outline; only inflated
    /// parts read it, so it's an autoclosure.
    func height(_ x: Double, _ y: Double, distance: @autoclosure () -> Double) -> Double {
        switch self {
        case let .inflated(depth, rxy, rz):
            let half = depth / 2
            let d = distance()
            if rxy <= 0 || d >= rxy { return half }
            let k = 1 - max(0, d) / rxy
            return half - rz + max(0, 1 - k * k).squareRoot() * rz
        case let .revolved(profile, axis, horizontal, volume):
            let (along, across) = horizontal ? (x, y) : (y, x)
            let r = profile.radius(at: along)
            return volume * max(0, r * r - (across - axis) * (across - axis)).squareRoot()
        }
    }

    /// Classifies a part with outline bounds `b`: shared horizontal axis, own vertical axis
    /// (multi-part bodies only), or inflated.
    static func classify(
        polys: [[Point]], bounds b: AvatarBounds, sharedAxis: Double?, canRevolveAlone: Bool, gridStep: Double, volume: Double
    ) -> PartShape {
        if let sharedAxis {
            if let profile = Profile(polys, rows: false, low: b.x0, high: b.x1, center: sharedAxis) {
                return .revolved(profile, axis: sharedAxis, horizontal: true, volume: volume)
            }
        } else if canRevolveAlone, let profile = Profile(polys, rows: true, low: b.y0, high: b.y1, center: b.center.x) {
            return .revolved(profile, axis: b.center.x, horizontal: false, volume: volume)
        }
        let coarse = DepthGrid(polys, b, step: max(gridStep, 0.6)) { _, _, _ in 0 }
        let thickness = 2 * coarse.signedDistance.reduce(0, max)
        let depth = inflatedDepth(thickness: thickness, b, volume: volume)
        return .inflated(depth: depth, rxy: min(thickness / 2, depth / 2) * 0.9, rz: depth / 2 * 0.85)
    }

    /// As deep as the part is thick, but tall slender parts get up to 2.4× so they read as discs.
    private static func inflatedDepth(thickness: Double, _ b: AvatarBounds, volume: Double) -> Double {
        let long = max(b.width, b.height)
        let raw = 0.8 * max(thickness, min(0.4 * long, 2.4 * thickness))
        return min(maxPartDepth, max(3, raw)) * volume
    }
}

/// Half-widths of a part along rows (or columns).
struct Profile {
    private let start: Double
    private let step: Double
    let radii: [Double]

    /// Nil unless every line crosses the part as one interval centered on `center`.
    init?(_ polys: [[Point]], rows: Bool, low: Double, high: Double, center: Double) {
        let step = 0.2
        let n = max(2, Int(((high - low) / step).rounded(.up)) + 1)
        var radii = [Double](repeating: 0, count: n)
        var span = 0.0
        var mids: [Double] = []
        for k in 0..<n {
            let s = min(high - 0.01, max(low + 0.01, low + Double(k) * step))
            let xs = crossings(polys, rows: rows, at: s)
            if xs.isEmpty { continue }
            if xs.count != 2 { return nil }
            radii[k] = (xs[1] - xs[0]) / 2
            span = max(span, xs[1] - xs[0])
            mids.append((xs[0] + xs[1]) / 2)
        }
        let tolerance = max(0.8, 0.04 * span)
        if mids.isEmpty || mids.contains(where: { abs($0 - center) > tolerance }) { return nil }
        start = low
        self.step = step
        self.radii = radii
    }

    func radius(at s: Double) -> Double {
        let t = (s - start) / step
        if t < 0 || t > Double(radii.count - 1) { return 0 }
        let k = min(radii.count - 2, Int(t.rounded(.down)))
        return radii[k] + (radii[k + 1] - radii[k]) * (t - Double(k))
    }
}

private func crossings(_ polys: [[Point]], rows: Bool, at s: Double) -> [Double] {
    var out: [Double] = []
    forEachEdge(polys) { p, q in
        let (pa, pb, qa, qb) = rows ? (p.y, p.x, q.y, q.x) : (p.x, p.y, q.x, q.y)
        if (pa <= s && qa > s) || (qa <= s && pa > s) { out.append(pb + (s - pa) * (qb - pb) / (qa - pa)) }
    }
    return out.sorted()
}

/// Horizontal axis of revolution, if the body looks like a turned object seen from the side: at
/// least two parts, wider than tall, mirror-symmetric about y = axis and every part centered on it.
func sharedRevolveAxis(_ body: BodyAnalysis) -> Double? {
    let b = body.bounds
    let outlines = body.subpaths.filter { !$0.isHole }
    if outlines.count < 2 || b.width < 1.1 * b.height { return nil }
    let axis = b.center.y
    for outline in outlines where abs(polygonBounds(outline.polys).center.y - axis) > 1.5 { return nil }
    var filled = 0, off = 0
    let xs = accumulatedSamples(from: b.x0 + 0.5, to: b.x1, by: 1)
    var top = [UInt8](repeating: 0, count: xs.count), bottom = top
    for y in accumulatedSamples(from: b.y0 + 0.5, to: axis, by: 1) {
        insideRow(body.polys, y: y, xs: xs, out: &top)
        insideRow(body.polys, y: 2 * axis - y, xs: xs, out: &bottom)
        for k in xs.indices {
            if top[k] != 0 || bottom[k] != 0 { filled += 1 }
            if top[k] != bottom[k] { off += 1 }
        }
    }
    return filled > 0 && Double(off) / Double(filled) < 0.02 ? axis : nil
}
