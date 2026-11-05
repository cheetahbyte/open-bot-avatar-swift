struct BodySubpath {
    var segments: [AvatarPathSegment]
    var d: String
    var polys: [[Point]]
    /// Inside the cut-out, when the subpath cuts a hole rather than adding fill.
    var cutProbe: Point?

    var isHole: Bool { cutProbe != nil }
}

struct BodyAnalysis {
    var polys: [[Point]]
    var bounds: AvatarBounds
    var area: Double
    var subpaths: [BodySubpath]
}

func analyzeBody(_ path: String) throws(PathError) -> BodyAnalysis {
    let segments = try parsePath(path)
    let polys = flattenPath(segments)
    let b = polygonBounds(polys)
    var subpaths: [BodySubpath] = []
    for sub in splitSubpaths(segments) {
        let own = flattenPath(sub)
        if own.isEmpty { continue }
        let ob = polygonBounds(own)
        var inside = 0.0, cut = 0.0
        var cutProbe: Point?
        // Small subpaths (buttons, sockets) need a fine grid; big ones classify fine on a coarser one.
        let step = ob.width * ob.height < 900 ? 0.5 : 1.0
        let alone = own.count == polys.count
        let xs = accumulatedSamples(from: ob.x0.rounded(.down) + step / 2, to: ob.x1, by: step)
        var mine = [UInt8](repeating: 0, count: xs.count), all = mine
        for y in accumulatedSamples(from: ob.y0.rounded(.down) + step / 2, to: ob.y1, by: step) {
            insideRow(own, y: y, xs: xs, out: &mine)
            if !alone { insideRow(polys, y: y, xs: xs, out: &all) }
            for k in xs.indices where mine[k] != 0 {
                inside += 1
                if !alone && all[k] == 0 {
                    cut += 1
                    if cutProbe == nil { cutProbe = Point(x: xs[k], y: y) }
                }
            }
        }
        let isHole = inside > 0 && cut / inside > 0.6
        subpaths.append(BodySubpath(segments: sub, d: serializePath(sub), polys: own, cutProbe: isHole ? cutProbe : nil))
    }
    return BodyAnalysis(polys: polys, bounds: b, area: filledArea(polys, b), subpaths: subpaths)
}
