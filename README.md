# Open Bot Avatar for Swift

A dependency-free Swift port of [Open Bot Avatar](https://github.com/DominikScholz/open-bot-avatar) for iOS and macOS.

This port tracks upstream 0.3.0, pinned at `5e64c081971eb296f562544641bad37d40fb36b6`.
It includes six states, independent moods, morphing eyes, animated marks, gradient ribbons, and smoother volume contours.

The definition contract remains v1: one SVG silhouette path and an eye placement.
The renderer owns color, implied volume, state, mood, and gaze; definitions don't store animation settings.

## Requirements

- iOS 17 or macOS 14
- Swift 6 tools

## Install

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/cheetahbyte/open-bot-avatar-swift.git", from: "0.1.0")
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

struct BotHeader: View {
    var isWorking: Bool

    var body: some View {
        AvatarView(
            AvatarCatalog.definition(id: "mug")!,
            color: .orange,
            state: isWorking ? .working : .idle,
            mood: .neutral,
            gaze: .pointer
        )
        .frame(width: 96, height: 96)
    }
}
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
| `state` | `.idle` (default), `.thinking`, `.working`, `.waiting`, `.blocked`, or `.done`. |
| `mood` | `.neutral` (default) or `.happy`, independently of state. |
| `gaze` | `.idle` (default), `.pointer`, `.look(AvatarLook)`, or `.hold`. |
| `rotation` | Extra rotation on top of the resting view, in radians. |
| `depth` | Volume, from 0 (flat) to 14. The default is 6. |
| `motion` | `.system` (default), `.full`, or `.reduced`. |
| `still` | Draws once and never animates. Use it for lists and thumbnails. |
| `label` | Accessible name. The default is the definition's name. Use `""` for a decorative avatar. |

The deprecated `mood: .idle` and `mood: .thinking` arguments still work.
Use `state: .idle, mood: .neutral` and `state: .thinking, mood: .neutral` instead.
An explicit `state` overrides the state inferred from a legacy mood.

With `.system`, the view follows the system's Reduce Motion setting.
Reduced motion disables turns, hops, blinking, and ribbons while retaining calm marks, eye shapes, and explicit gaze.
A view mounted in `.done` starts at rest; changing into `.done` starts its celebration.

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

`PreparedAvatar` holds a validated definition with its volume built.
Preparation costs more than producing a frame; reuse the prepared volume across frames.
Keep one instance per definition and depth, or use `PreparedAvatar.cached`:

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

`AvatarFrame` is plain data. Paint `shapes` in order, inside the `root` transform.
Slices reference `frame.paths`; the table retains prepared body paths even when a mark replaces the body.
Ribbons carry their own paths, fill colors, and linear gradients.
Eyes can be pills, stroked arcs, or filled morph paths.
SVG output includes only referenced body and mark paths.

Pass `stateAge` in seconds to animate a celebration from state entry.
Without it, a standalone `.done` frame rests; `.working` uses `time` for its sweep clock.
The `time` option is the independent animation clock, also in seconds.

To drive animation, keep one `AvatarAnimator` and call `step` once per frame:

```swift
var animator = AvatarAnimator()
let step = animator.step(.init(now: 12.5, mood: .happy, state: .working))
let animatedOptions = AvatarFrameOptions(
    time: 1.5,
    mood: step.mood,
    gaze: step.gaze,
    state: step.state,
    stateAge: step.stateAge
)
let animatedFrame = avatar.frame(animatedOptions)
```

Use a monotonic wall clock for `now`, in seconds.
Keep the animator between frames so gaze, interrupted blends, and state clocks remain continuous.
`AvatarMoodState(state:mood:age:)` also represents a settled state for custom animation drivers.
The original `.settled` and `.easing` cases remain available.

## Run development checks

Run the simulator-free tests on macOS:

```sh
swift build
swift test
```

The engine tests use Foundation; painter tests use offscreen Core Graphics without an app host or simulator.
Parity fixtures cover every state and mood, legacy inputs, reduced motion, interrupted blends, and animator clocks.
Representative frames cover the mug, barbell, controller, asymmetric chat silhouette, egg, and primitive shapes.
Checks include eye morphs, marks, ribbon geometry, exact palette colors, SVG output, and sampled volume contours.
Numeric poses and matrices use `1e-9` absolute tolerance.
Serialized paths retain command structure except independently simplified revolved contours.
Those contours allow `0.04` units plus differential coordinate rounding, bounded at `0.055` units.

## Regenerate upstream data

`AvatarCatalog` contains upstream's starters and gallery.
Regenerate the catalog and plain JSON parity fixtures with Node 22.18 or later:

```sh
node scripts/sync-upstream.mjs PATH_TO_OPEN_BOT_AVATAR
```

Replace `PATH_TO_OPEN_BOT_AVATAR` with a pristine checkout of the pinned upstream revision.
The scripts verify the revision and reject tracked changes.
Without an argument, they use `../.build/open-bot-avatar-0.3.0` relative to this package.
They import TypeScript directly; no npm dependencies or Swift-generated expectations are involved.

Fixtures live in `Tests/OpenBotAvatarTests/Fixtures/upstream-0.3.0.json` and record their source revision.
Only six representative cases include SVG snapshots, rather than snapshots of every catalog avatar.
To regenerate only the catalog, run `node scripts/sync-catalog.mjs PATH_TO_OPEN_BOT_AVATAR`.

## Differences from the TypeScript package

- The CSS 3D scene renderer isn't included. `AvatarView` always paints to a single bitmap.
- `silhouetteSeams`, `faceRoom`, and the strict validation checks aren't included. They're authoring tools for generated avatars.
- Colors are `AvatarColor` values in the engine and SwiftUI `Color` values in the view, not CSS strings.
- `AvatarView` prepares new geometry off the main thread and stays empty until preparation finishes.
- Each animated avatar has its own display link.

SVG parity checks normalize definition identifiers and definition order, but preserve paint order and transforms.
Some revolved cross-sections differ within the contour tolerance described in the development checks.

## License

[MIT](LICENSE)
