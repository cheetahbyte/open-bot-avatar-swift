/// Definitions that ship with the library. `AvatarCatalog+Data.generated.swift` holds the data; run
/// `scripts/sync-catalog.mjs` to refresh it from the open-bot-avatar repository.
public enum AvatarCatalog {
    /// Starters, the same set as the npm package's `examples`.
    public static var examples: [AvatarDefinition] { generatedExamples }
    /// The community gallery, by name.
    public static var gallery: [AvatarDefinition] { generatedGallery }
    public static var all: [AvatarDefinition] { examples + gallery }

    public static func definition(id: String) -> AvatarDefinition? {
        all.first { $0.id == id }
    }

    /// The color a catalog avatar is shown in until someone picks another.
    public static func color(id: String) -> AvatarColor {
        generatedColors[id].flatMap(AvatarColor.init(hex:)) ?? .defaultBody
    }
}
