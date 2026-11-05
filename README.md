# Open Bot Avatar for Swift

A Swift package that renders [Open Bot Avatar](https://github.com/DominikScholz/open-bot-avatar) definitions on iOS and macOS. It adapts the TypeScript engine to native Apple frameworks and has no dependencies.

A definition is one SVG path and an eye placement. The library infers a volume from the outline and adds idle motion, moods, and gaze.

## Requirements

- iOS 17 or macOS 14
- Swift 6 tools

## Install

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/cheetahbyte/open-bot-avatar-swift.git", branch: "main")
```

The package has two products:

| Product | Contents | Imports |
| --- | --- | --- |
| `OpenBotAvatar` | Validation, volume, poses, frames, SVG output, and the catalog | Foundation |
| `OpenBotAvatarUI` | `AvatarView`, the Core Graphics painter, and image output | SwiftUI, Core Animation |

## Show an avatar

`AvatarView` fills the largest centered square it's offered:

```swift
import OpenBotAvatar
import OpenBotAvatarUI
import SwiftUI

struct AgentHeader: View {
    var isWorking: Bool

    var body: some View {
        AvatarView(
            AvatarCatalog.definition(id: "mug")!,
            color: .orange,
            mood: isWorking ? .thinking : .idle,
            gaze: .pointer
        )
        .frame(width: 96, height: 96)
    }
}
```

Change any argument and the avatar eases to the new state.

| Argument | Description |
| --- | --- |
| `definition` | The avatar. Required. |
| `color`, `eyeColor` | Any SwiftUI `Color`. Dynamic colors follow the appearance. |
| `mood` | `.idle` (default), `.thinking`, or `.happy`. |
| `gaze` | `.idle` (default), `.pointer`, `.look(AvatarLook)`, or `.hold`. |
| `rotation` | Extra rotation on top of the resting view, in radians. |
| `depth` | Volume, from 0 (flat) to 14. The default is 6. |
| `motion` | `.system` (default), `.full`, or `.reduced`. |
| `still` | Draws once and never animates. Use it for lists and thumbnails. |
| `label` | Accessible name. The default is the definition's name. Use `""` for a decorative avatar. |

## Validate a definition

Validate any definition that you didn't write:

```swift
switch AvatarDefinition.validate(json: data) {
case .success(let definition):
    show(definition)
case .failure(let error):
    print(error.errors)
}
```

The rules are in the [avatar definition contract](https://github.com/DominikScholz/open-bot-avatar/blob/main/docs/avatar-contract.md).

## Render without a view

`PreparedAvatar` holds a validated definition with its volume built. Building takes about 10 ms, and a frame takes far less. Keep one instance per definition and depth, or use `PreparedAvatar.cached`:

```swift
let avatar = try PreparedAvatar.cached(definition)
let options = AvatarFrameOptions(color: AvatarColor(hex: "#1fbf68") ?? .defaultBody)

let svg = avatar.svg(options, size: 256)
let frame = avatar.frame(options)
let image = avatar.image(options, pixels: 512) // Needs OpenBotAvatarUI.
```

`AvatarFrame` is plain data, so you can draw it with any vector renderer. Paint `shapes` in order, inside `root`.

To drive your own animation, call `AvatarAnimator.step` once per frame and pass its gaze and mood to `AvatarFrameOptions`.

## Update the catalog

`AvatarCatalog` holds the starters and the gallery from the TypeScript repository. To refresh it, run the following command:

```sh
node scripts/sync-catalog.mjs PATH_TO_OPEN_BOT_AVATAR
```

Replace `PATH_TO_OPEN_BOT_AVATAR` with the path to your checkout. The script needs Node 22.18 or later.

## Differences from the TypeScript package

- The CSS 3D scene renderer isn't included. `AvatarView` always paints to a single bitmap.
- `silhouetteSeams`, `faceRoom`, and the strict validation checks aren't included. They're authoring tools for generated avatars.
- Colors are `AvatarColor` values in the engine and SwiftUI `Color` values in the view, not CSS strings.
- `AvatarView` builds a new avatar off the main thread, so it stays empty for its first few milliseconds.
- Each animated avatar has its own display link.

SVG output matches the TypeScript engine, apart from rounding differences in a few cross-sections of revolved parts. Those differences stay within the 0.04-unit simplification tolerance.

## License

[MIT](LICENSE)
