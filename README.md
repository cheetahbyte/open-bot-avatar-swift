# Open Bot Avatar for Swift

A native Swift and SwiftUI port of [Open Bot Avatar](https://github.com/DominikScholz/open-bot-avatar) by Dominik Scholz, with no dependencies.

Tracks [upstream 0.3.0](https://github.com/DominikScholz/open-bot-avatar/tree/5e64c081971eb296f562544641bad37d40fb36b6): six states, independent moods, morphing eyes, replacement marks, and gradient ribbons.
Definitions use the unchanged v1 contract: one SVG silhouette path and an eye placement.

Major and minor versions follow upstream. Patch releases can include native-only fixes, so patch numbers can differ.
The linked upstream revision identifies the engine used by this release. See the [changelog](CHANGELOG.md) for upgrade notes.

## Requirements

- iOS 17 or macOS 14
- Swift 6 tools

## Install

Add the `0.3.x` release family to your `Package.swift` dependencies:

```swift
.package(
    url: "https://github.com/cheetahbyte/open-bot-avatar-swift.git",
    "0.3.0"..<"0.4.0"
)
```

Choose a product:

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

AvatarView(
    AvatarCatalog.definition(id: "mug")!,
    color: .orange,
    state: .working,
    mood: .happy,
    gaze: .pointer
)
.frame(width: 96, height: 96)
```

State and mood changes ease from the current pose, including an interrupted transition.
A mood change doesn't restart the state's clock.

| State | Appearance |
| --- | --- |
| `.idle` | Breathes and looks around; hops when happy. |
| `.thinking` | Turns into three animated dots. |
| `.working` | Attends to work and periodically sweeps ribbons around the body. |
| `.waiting` | Leans with slit eyes; happy moods keep their arcs. |
| `.blocked` | Turns into an exclamation mark. |
| `.done` | Celebrates with turns and ribbons, rests, and repeats. |

| Argument | Description |
| --- | --- |
| `definition` | The avatar. Required. |
| `color`, `eyeColor` | Any SwiftUI `Color`. Dynamic colors follow the appearance. |
| `state` | Activity state; defaults to `.idle`. |
| `mood` | `.neutral` (default) or `.happy`, independently of state. |
| `gaze` | `.idle` (default), `.pointer`, `.look(AvatarLook)`, or `.hold`. |
| `rotation` | Extra rotation on top of the resting view, in radians. |
| `depth` | Volume, from 0 (flat) to 14. The default is 6. |
| `motion` | `.system` (default), `.full`, or `.reduced`. |
| `still` | Draws once and never animates. Use it for lists and thumbnails. |
| `label` | Accessible name. The default is the definition's name. Use `""` for a decorative avatar. |

Reduced motion keeps the body and marks still, stops blinking, and omits ribbons; eye shapes and explicit gaze remain.
A view mounted in `.done` starts at rest; changing into `.done` starts its celebration.

Legacy `mood: .idle` and `mood: .thinking` calls still work but are deprecated.
Use `state` instead; an explicit state takes precedence.
Custom renderers must handle the new ribbon shapes and filled eye paths.

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

The rules are in the [avatar definition contract](https://github.com/DominikScholz/open-bot-avatar/blob/5e64c081971eb296f562544641bad37d40fb36b6/docs/avatar-contract.md).

## Render without a view

Prepare geometry off the main thread and reuse it across frames.
`PreparedAvatar.cached` shares prepared geometry by definition and depth:

```swift
let avatar = try PreparedAvatar.cached(definition)
let options = AvatarFrameOptions(
    color: AvatarColor(hex: "#1fbf68") ?? .defaultBody,
    time: 1.7,
    mood: .settled(.happy),
    state: .done,
    stateAge: 1.7
)

let svg = avatar.svg(options, size: 256)
let frame = avatar.frame(options)
let image = avatar.image(options, pixels: 512) // Needs OpenBotAvatarUI.
```

For custom rendering, paint `frame.shapes` in order inside `frame.root`.
Slices reference `frame.paths`; eyes are pills, stroked arcs, or filled paths.
Ribbons carry their own paths and linear gradients.

Both clocks use seconds: `time` drives ambient motion, and `stateAge` measures time since state entry.
Without `stateAge`, `.done` rests and `.working` uses `time` for its sweep clock.

For custom animation hosts, keep one `AvatarAnimator` and call `step` once per frame.
Use a monotonic clock for `now`, in seconds.
Pass the returned `mood`, `gaze`, `state`, and `stateAge` to `AvatarFrameOptions`.

## Run development checks

Run the simulator-free tests on macOS:

```sh
swift build
swift test
```

Tests compare poses, frames, SVG output, and animation clocks against fixtures generated by the pinned upstream engine.
Painter tests use offscreen Core Graphics. No app host or simulator is required.

## Regenerate upstream data

With Node 22.18 or later, regenerate the catalog and parity fixtures:

```sh
node scripts/sync-upstream.mjs PATH_TO_OPEN_BOT_AVATAR
```

Replace `PATH_TO_OPEN_BOT_AVATAR` with a clean checkout of the linked upstream revision.
The scripts verify the revision and reject tracked changes.
To update only the catalog, run `node scripts/sync-catalog.mjs PATH_TO_OPEN_BOT_AVATAR`.

## Differences from the TypeScript package

- The CSS 3D scene renderer isn't included. `AvatarView` always paints to a single bitmap.
- `silhouetteSeams`, `faceRoom`, and the strict validation checks aren't included. They're authoring tools for generated avatars.
- Colors are `AvatarColor` values in the engine and SwiftUI `Color` values in the view, not CSS strings.
- `AvatarView` prepares geometry off the main thread and stays empty until preparation finishes.
- Some revolved cross-sections differ slightly because of floating-point rounding and contour simplification.

## License and attribution

[MIT](LICENSE). Based on [Open Bot Avatar](https://github.com/DominikScholz/open-bot-avatar) by Dominik Scholz.
