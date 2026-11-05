import Foundation

/// Why a definition was rejected. `errors` are written to be shown to a person or a model.
public struct AvatarValidationError: Error, Equatable, Sendable, LocalizedError {
    public let errors: [String]

    public init(errors: [String]) {
        self.errors = errors
    }

    public var errorDescription: String? {
        "Invalid avatar definition: \(errors.joined(separator: "; "))"
    }
}

extension AvatarDefinition {
    /// Checks a definition you didn't write. The result carries the normalized definition.
    public static func validate(json: Data) -> Result<AvatarDefinition, AvatarValidationError> {
        guard let object = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else {
            return .failure(AvatarValidationError(errors: ["definition must be valid JSON"]))
        }
        return validateObject(object)
    }

    public static func validate(json: String) -> Result<AvatarDefinition, AvatarValidationError> {
        validate(json: Data(json.utf8))
    }

    /// Reads and validates JSON. Throws `AvatarValidationError`.
    public init(validating json: Data) throws {
        self = try Self.validate(json: json).get()
    }

    /// The normalized form of this definition, if it holds up.
    public func validated() -> Result<AvatarDefinition, AvatarValidationError> {
        Self.validateObject([
            "version": version,
            "id": id,
            "name": name,
            "body": ["path": body.path],
            "eyes": ["x": eyes.x, "y": eyes.y, "spacing": eyes.spacing, "scale": eyes.scale]
        ] as [String: Any])
    }
}

private let topKeys = ["version", "id", "name", "body", "eyes"]
private let eyeKeys = ["x", "y", "spacing", "scale"]
private let bodyMin = 6.0
private let bodyMax = 94.0

/// A JSON number that isn't `true` or `false`, which Foundation also hands back as NSNumber.
private func number(_ value: Any?) -> Double? {
    if let n = value as? NSNumber {
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : n.doubleValue
    }
    return value as? Double
}

private func finite(_ value: Any?) -> Double? {
    number(value).flatMap { $0.isFinite ? $0 : nil }
}

private func isSlug(_ id: String) -> Bool {
    let bytes = Array(id.utf8)
    guard (1...40).contains(bytes.count), bytes.first != 45, bytes.last != 45 else { return false }
    return bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
}


extension AvatarDefinition {
    fileprivate static func validateObject(_ input: Any) -> Result<AvatarDefinition, AvatarValidationError> {
        guard let record = input as? [String: Any] else {
            return .failure(AvatarValidationError(errors: ["definition must be a JSON object"]))
        }
        var errors: [String] = []

        for key in record.keys.sorted() where !topKeys.contains(key) {
            errors.append("unknown field \"\(key)\" (allowed: \(topKeys.joined(separator: ", ")))")
        }
        if number(record["version"]) != 1 { errors.append("version must be 1") }

        let id = record["id"] as? String
        if id.map(isSlug) != true { errors.append("id must be a lowercase slug of 1-40 chars [a-z0-9-]") }

        let name = (record["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unprintable = name.unicodeScalars.contains { $0.value < 0x20 || $0 == "<" || $0 == ">" }
        if name.isEmpty || name.utf16.count > 40 || unprintable {
            errors.append("name must be 1-40 printable characters without < or >")
        }

        var path: String?
        if let body = record["body"] as? [String: Any] {
            for key in body.keys.sorted() where key != "path" {
                errors.append("unknown field \"body.\(key)\" (only \"path\" is allowed)")
            }
            path = body["path"] as? String
            if path == nil { errors.append("body.path must be a string") }
        } else {
            errors.append("body must be an object { \"path\": \"...\" }")
        }

        var eyes: AvatarEyes?
        if let e = record["eyes"] as? [String: Any] {
            for key in e.keys.sorted() where !eyeKeys.contains(key) {
                errors.append("unknown field \"eyes.\(key)\" (allowed: \(eyeKeys.joined(separator: ", ")))")
            }
            let bad = eyeKeys.filter { finite(e[$0]) == nil }
            if !bad.isEmpty {
                errors.append("eyes.\(bad.joined(separator: ", eyes.")) must be finite numbers")
            } else if let x = finite(e["x"]), let y = finite(e["y"]), let spacing = finite(e["spacing"]), let scale = finite(e["scale"]) {
                eyes = AvatarEyes(x: x, y: y, spacing: spacing, scale: scale)
                if scale < 0.6 || scale > 1.8 {
                    errors.append("eyes.scale \(numberText(scale)) out of range 0.6..1.8")
                }
                let minSpacing = EyeMetrics.width * scale * 1.75
                if spacing < minSpacing || spacing > 40 {
                    errors.append("eyes.spacing \(numberText(spacing)) out of range \(rounded1(minSpacing))..40 for scale \(numberText(scale))")
                }
            }
        } else {
            errors.append("eyes must be an object { x, y, spacing, scale }")
        }

        var normalized = ""
        var analysis: BodyAnalysis?
        if let path {
            do {
                normalized = serializePath(try parsePath(path))
                analysis = try analyzeBody(normalized)
            } catch {
                errors.append("body.path: \((error as? PathError)?.message ?? "\(error)")")
            }
        }

        if let analysis {
            let b = analysis.bounds
            var outside: [String] = []
            if b.minX < bodyMin { outside.append("left edge x=\(rounded1(b.minX))") }
            if b.minY < bodyMin { outside.append("top edge y=\(rounded1(b.minY))") }
            if b.maxX > bodyMax { outside.append("right edge x=\(rounded1(b.maxX))") }
            if b.maxY > bodyMax { outside.append("bottom edge y=\(rounded1(b.maxY))") }
            if !outside.isEmpty {
                errors.append("body.path leaves the safe area (\(outside.joined(separator: ", "))); keep geometry within 8..92")
            }
            if max(b.width, b.height) < 40 || min(b.width, b.height) < 14 {
                errors.append("body is too small (\(rounded1(b.width))x\(rounded1(b.height))); use at least 40 units on the long side and 14 on the short side")
            }
            if analysis.area < 600 {
                errors.append("body fill area \(numberText(analysis.area)) is too thin to carry eyes; must be at least 600 units²")
            }
            if let eyes, let miss = eyesMiss(analysis.polys, eyes, margin: EyeMetrics.margin) {
                errors.append(
                    "eyes must sit inside the body with \(numberText(EyeMetrics.margin)) units margin; point (\(rounded1(miss.x)), \(rounded1(miss.y))) is outside or in a hole. "
                        + "Move eyes.x/y toward the widest solid area, reduce spacing or scale.")
            }
        }

        guard errors.isEmpty, let eyes, let id else { return .failure(AvatarValidationError(errors: errors)) }
        return .success(AvatarDefinition(id: id, name: name, body: AvatarBody(path: normalized), eyes: eyes))
    }
}
