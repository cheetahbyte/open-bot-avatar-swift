import OpenBotAvatar
import SwiftUI

/// Where a live avatar looks.
public enum AvatarGazeBehavior: Hashable, Sendable {
    /// Idle eye wander.
    case idle
    /// Eyes look and the body turns toward the mouse, pen or finger anywhere in the window.
    case pointer
    /// A fixed direction.
    case look(AvatarLook)
    /// Keep looking where it looks now, for example while the user drags the view.
    case hold
}

public enum AvatarMotionPreference: Hashable, Sendable {
    /// Follow the system's Reduce Motion setting.
    case system
    case full
    case reduced
}

extension Color {
    public init(_ color: AvatarColor) {
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}

/// A live avatar. It fills the largest centered square it is offered and overhangs it while turning.
/// Animation pauses out of view, and input passes through to the views around it.
public struct AvatarView: View {
    private let definition: AvatarDefinition
    private let color: Color
    private let eyeColor: Color
    private let mood: AvatarMood
    private let gaze: AvatarGazeBehavior
    private let rotation: AvatarViewRotation?
    private let depth: Double
    private let motion: AvatarMotionPreference
    private let still: Bool
    private let label: String?

    /// - Parameters:
    ///   - rotation: Extra rotation on top of the resting view, for example from drag-to-turn.
    ///   - depth: Volume amount, 0 (flat) to 14.
    ///   - still: Draw once and never animate, for thumbnails and lists.
    ///   - label: Accessible name; defaults to the definition's name. `""` marks it decorative.
    public init(
        _ definition: AvatarDefinition,
        color: Color = Color(.defaultBody),
        eyeColor: Color = Color(.defaultEyes),
        mood: AvatarMood = .idle,
        gaze: AvatarGazeBehavior = .idle,
        rotation: AvatarViewRotation? = nil,
        depth: Double = PreparedAvatar.defaultDepth,
        motion: AvatarMotionPreference = .system,
        still: Bool = false,
        label: String? = nil
    ) {
        self.definition = definition
        self.color = color
        self.eyeColor = eyeColor
        self.mood = mood
        self.gaze = gaze
        self.rotation = rotation
        self.depth = depth
        self.motion = motion
        self.still = still
        self.label = label
    }

    public var body: some View {
        let surface = AvatarSurface(
            definition: definition, color: color, eyeColor: eyeColor, mood: mood, gaze: gaze, rotation: rotation,
            depth: depth, motion: motion, still: still
        )
        .aspectRatio(1, contentMode: .fit)
        if label == "" {
            surface.accessibilityHidden(true)
        } else {
            surface
                .accessibilityElement()
                .accessibilityLabel(label ?? definition.name)
                .accessibilityAddTraits(.isImage)
        }
    }
}

private struct AvatarSurface {
    let definition: AvatarDefinition
    let color: Color
    let eyeColor: Color
    let mood: AvatarMood
    let gaze: AvatarGazeBehavior
    let rotation: AvatarViewRotation?
    let depth: Double
    let motion: AvatarMotionPreference
    let still: Bool

    @MainActor
    private func sync(_ view: AvatarSurfaceView, _ environment: EnvironmentValues) {
        let reduced = switch motion {
        case .system: environment.accessibilityReduceMotion
        case .full: false
        case .reduced: true
        }
        view.update(AvatarSurfaceState(
            definition: definition, depth: depth, mood: mood, gaze: gaze, rotation: rotation, reducedMotion: reduced,
            still: still, fill: color.resolve(in: environment).cgColor, ink: eyeColor.resolve(in: environment).cgColor))
    }
}

#if os(macOS)
    extension AvatarSurface: NSViewRepresentable {
        func makeNSView(context: Context) -> AvatarSurfaceView { AvatarSurfaceView() }
        func updateNSView(_ view: AvatarSurfaceView, context: Context) { sync(view, context.environment) }
    }
#else
    extension AvatarSurface: UIViewRepresentable {
        func makeUIView(context: Context) -> AvatarSurfaceView { AvatarSurfaceView() }
        func updateUIView(_ view: AvatarSurfaceView, context: Context) { sync(view, context.environment) }
    }
#endif
