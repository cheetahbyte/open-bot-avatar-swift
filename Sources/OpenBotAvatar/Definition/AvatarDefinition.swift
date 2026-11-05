/// Avatar definition contract v1: geometry only. Color, volume, view, gaze, blinking and motion
/// belong to the renderer.
public struct AvatarDefinition: Codable, Hashable, Identifiable, Sendable {
    public var version: Int
    /// Lowercase slug, for example `controller`.
    public var id: String
    public var name: String
    public var body: AvatarBody
    public var eyes: AvatarEyes

    public init(version: Int = 1, id: String, name: String, body: AvatarBody, eyes: AvatarEyes) {
        self.version = version
        self.id = id
        self.name = name
        self.body = body
        self.eyes = eyes
    }
}

public struct AvatarBody: Codable, Hashable, Sendable {
    /// One filled SVG path in a `0 0 100 100` box, nonzero fill rule.
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct AvatarEyes: Codable, Hashable, Sendable {
    /// Center of the eye pair, viewBox units.
    public var x: Double
    public var y: Double
    /// Center-to-center distance, viewBox units.
    public var spacing: Double
    /// 1 means each neutral eye is about 4 units wide and 11 tall.
    public var scale: Double

    public init(x: Double, y: Double, spacing: Double, scale: Double) {
        self.x = x
        self.y = y
        self.spacing = spacing
        self.scale = scale
    }
}
