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

private let topKeys = ["version", "id", "name", "body", "eyes"]
private let eyeKeys = ["x", "y", "spacing", "scale"]
private let bodyMin = 6.0
private let bodyMax = 94.0

/// A JSON number that isn't `true` or `false`, which Foundation also hands back as NSNumber.
private func number(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

private func isSlug(_ id: String) -> Bool {
    let bytes = Array(id.utf8)
    guard (1...40).contains(bytes.count), bytes.first != 45, bytes.last != 45 else { return false }
    return bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
}

/// A definition that passed validation, with the body analysis that proved it.
struct ValidatedAvatar {
    var definition: AvatarDefinition
    var body: BodyAnalysis
}

/// The fields of a definition as far as they could be read, and what was wrong with their shape.
private struct Candidate {
    var version: Double?
    var id: String?
    var name: String?
    var path: String?
    var eyes: AvatarEyes?
    var unknownFields: [String] = []
    var bodyErrors: [String] = []
    var eyeErrors: [String] = []

    init(_ definition: AvatarDefinition) {
        version = Double(definition.version)
        id = definition.id
        name = definition.name
        path = definition.body.path
        readEyes(definition.eyes.x, definition.eyes.y, definition.eyes.spacing, definition.eyes.scale)
    }

    init?(json: Any) {
        guard let record = json as? [String: Any] else { return nil }
        for key in record.keys.sorted() where !topKeys.contains(key) {
            unknownFields.append("unknown field \"\(key)\" (allowed: \(topKeys.joined(separator: ", ")))")
        }
        version = number(record["version"])
        id = record["id"] as? String
        name = record["name"] as? String
        if let body = record["body"] as? [String: Any] {
            for key in body.keys.sorted() where key != "path" {
                bodyErrors.append("unknown field \"body.\(key)\" (only \"path\" is allowed)")
            }
            path = body["path"] as? String
            if path == nil { bodyErrors.append("body.path must be a string") }
        } else {
            bodyErrors.append("body must be an object { \"path\": \"...\" }")
        }
        if let e = record["eyes"] as? [String: Any] {
            for key in e.keys.sorted() where !eyeKeys.contains(key) {
                eyeErrors.append("unknown field \"eyes.\(key)\" (allowed: \(eyeKeys.joined(separator: ", ")))")
            }
            readEyes(number(e["x"]), number(e["y"]), number(e["spacing"]), number(e["scale"]))
        } else {
            eyeErrors.append("eyes must be an object { x, y, spacing, scale }")
        }
    }

    private mutating func readEyes(_ values: Double?...) {
        let finite = values.map { $0.flatMap { $0.isFinite ? $0 : nil } }
        let bad = zip(eyeKeys, finite).filter { $0.1 == nil }.map(\.0)
        if !bad.isEmpty {
            eyeErrors.append("eyes.\(bad.joined(separator: ", eyes.")) must be finite numbers")
            return
        }
        let v = finite.compactMap { $0 }
        eyes = AvatarEyes(x: v[0], y: v[1], spacing: v[2], scale: v[3])
    }
}

extension AvatarDefinition {
    /// Checks a definition you didn't write. The result carries the normalized definition.
    public static func validate(json: Data) -> Result<AvatarDefinition, AvatarValidationError> {
        guard let object = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else {
            return .failure(AvatarValidationError(errors: ["definition must be valid JSON"]))
        }
        guard let candidate = Candidate(json: object) else {
            return .failure(AvatarValidationError(errors: ["definition must be a JSON object"]))
        }
        return check(candidate).map(\.definition)
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
        validatedWithBody().map(\.definition)
    }

    func validatedWithBody() -> Result<ValidatedAvatar, AvatarValidationError> {
        Self.check(Candidate(self))
    }

    private static func check(_ candidate: Candidate) -> Result<ValidatedAvatar, AvatarValidationError> {
        var errors = candidate.unknownFields
        if candidate.version != 1 { errors.append("version must be 1") }

        let id = candidate.id
        if id.map(isSlug) != true { errors.append("id must be a lowercase slug of 1-40 chars [a-z0-9-]") }

        let name = candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unprintable = name.unicodeScalars.contains { $0.value < 0x20 || $0 == "<" || $0 == ">" }
        if name.isEmpty || name.utf16.count > 40 || unprintable {
            errors.append("name must be 1-40 printable characters without < or >")
        }

        errors += candidate.bodyErrors
        errors += candidate.eyeErrors
        let eyes = candidate.eyes
        if let eyes {
            if eyes.scale < 0.6 || eyes.scale > 1.8 {
                errors.append("eyes.scale \(numberText(eyes.scale)) out of range 0.6..1.8")
            }
            let minSpacing = EyeMetrics.width * eyes.scale * 1.75
            if eyes.spacing < minSpacing || eyes.spacing > 40 {
                errors.append("eyes.spacing \(numberText(eyes.spacing)) out of range \(rounded1(minSpacing))..40 for scale \(numberText(eyes.scale))")
            }
        }

        var normalized = ""
        var analysis: BodyAnalysis?
        if let path = candidate.path {
            do throws(PathError) {
                normalized = serializePath(try parsePath(path))
                analysis = try analyzeBody(normalized)
            } catch {
                errors.append("body.path: \(error.message)")
            }
        }

        if let analysis {
            let b = analysis.bounds
            var outside: [String] = []
            if b.x0 < bodyMin { outside.append("left edge x=\(rounded1(b.x0))") }
            if b.y0 < bodyMin { outside.append("top edge y=\(rounded1(b.y0))") }
            if b.x1 > bodyMax { outside.append("right edge x=\(rounded1(b.x1))") }
            if b.y1 > bodyMax { outside.append("bottom edge y=\(rounded1(b.y1))") }
            if !outside.isEmpty {
                errors.append("body.path leaves the safe area (\(outside.joined(separator: ", "))); keep geometry within 8..92")
            }
            if max(b.width, b.height) < 40 || min(b.width, b.height) < 14 {
                errors.append("body is too small (\(rounded1(b.width))x\(rounded1(b.height))); use at least 40 units on the long side and 14 on the short side")
            }
            if analysis.area < 600 {
                errors.append("body fill area \(numberText(analysis.area)) is too thin to carry eyes; must be at least 600 units²")
            }
            if let eyes, let miss = eyesMiss(analysis.polys, eyes) {
                errors.append(
                    "eyes must sit inside the body with \(numberText(EyeMetrics.margin)) units margin; point (\(rounded1(miss.x)), \(rounded1(miss.y))) is outside or in a hole. "
                        + "Move eyes.x/y toward the widest solid area, reduce spacing or scale.")
            }
        }

        guard errors.isEmpty, let eyes, let id, let analysis else { return .failure(AvatarValidationError(errors: errors)) }
        let definition = AvatarDefinition(id: id, name: name, body: AvatarBody(path: normalized), eyes: eyes)
        return .success(ValidatedAvatar(definition: definition, body: analysis))
    }
}
