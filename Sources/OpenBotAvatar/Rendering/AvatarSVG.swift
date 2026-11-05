extension PreparedAvatar {
    /// A standalone SVG still; `size` sets its width and height, nil leaves it fluid. Output is built
    /// only from numbers and the renderer's own markup.
    public func svg(_ options: AvatarFrameOptions = AvatarFrameOptions(), size: Double? = nil) -> String {
        let frame = frame(options)
        var slices: [(key: AvatarSliceKey, path: Int)] = []
        var body = ""
        let ink = frame.ink.hex
        for shape in frame.shapes {
            switch shape {
            case let .slice(key, path, matrix):
                slices.append((key, path))
                body += "<use href=\"#\(paths[path].id)\" transform=\"\(matrixText(matrix))\"/>"
            case let .eye(_, matrix, mark):
                body += "<g transform=\"\(matrixText(matrix))\">\(eyeMarkup(mark, ink: ink))</g>"
            }
        }
        // Defs follow the volume's slice order, not paint order, which matches the TypeScript output.
        slices.sort { ($0.key.part, $0.key.index) < ($1.key.part, $1.key.index) }
        var seen = Set<Int>()
        var defs = ""
        for slice in slices where seen.insert(slice.path).inserted {
            let path = paths[slice.path]
            defs += "<path id=\"\(path.id)\" d=\"\(path.d)\"\(path.evenOdd ? " fill-rule=\"evenodd\"" : "")/>"
        }
        var dimensions = ""
        if let size, size.isFinite, size > 0 {
            let text = rounded2(clamp(size, 8, 4096))
            dimensions = " width=\"\(text)\" height=\"\(text)\""
        }
        let label = escaped(frame.name)
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"\(dimensions) role=\"img\" aria-label=\"\(label)\" overflow=\"visible\">"
            + "<title>\(label)</title>"
            + "<defs>\(defs)</defs>"
            + "<g transform=\"\(matrixText(frame.root))\" fill=\"\(frame.color.hex)\">"
            + body
            + "</g></svg>"
    }
}

private func escaped(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        if "&<>\"'".unicodeScalars.contains(scalar) {
            out += "&#\(scalar.value);"
        } else {
            out.unicodeScalars.append(scalar)
        }
    }
    return out
}

private func matrixText(_ m: AvatarMatrix) -> String {
    let linear = [m.a, m.b, m.c, m.d].map { numberText(roundHalfUp($0 * 10000) / 10000) }
    return "matrix(\(linear.joined(separator: " ")) \(rounded2(m.e)) \(rounded2(m.f)))"
}

private func eyeMarkup(_ mark: AvatarEyeMark, ink: String) -> String {
    let f = rounded2
    switch mark {
    case let .pill(x, y, width, height, radius):
        return "<rect x=\"\(f(x))\" y=\"\(f(y))\" width=\"\(f(width))\" height=\"\(f(height))\" rx=\"\(f(radius))\" fill=\"\(ink)\"/>"
    case let .arc(startX, startY, controlX, controlY, endX, endY, strokeWidth):
        let d = "M\(f(startX)) \(f(startY))Q\(f(controlX)) \(f(controlY)) \(f(endX)) \(f(endY))"
        return "<path d=\"\(d)\" fill=\"none\" stroke=\"\(ink)\" stroke-width=\"\(f(strokeWidth))\" stroke-linecap=\"round\"/>"
    }
}
