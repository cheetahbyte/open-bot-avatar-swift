extension AvatarPathSegment {
    /// Parses engine-owned paths for painters in this package.
    package static func parse(svg: String) throws -> [AvatarPathSegment] {
        try parsePath(svg)
    }
}

extension AvatarMatrix {
    var inverted: AvatarMatrix {
        let det = a * d - b * c
        return AvatarMatrix(a: d / det, b: -b / det, c: -c / det, d: a / det,
                            e: (c * f - d * e) / det, f: (b * e - a * f) / det)
    }
}
