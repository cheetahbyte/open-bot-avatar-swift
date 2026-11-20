/// What to draw. Same inputs always produce the same frame.
public struct AvatarFrameOptions: Hashable, Sendable {
    public var color: AvatarColor
    public var eyeColor: AvatarColor
    /// Animation clock, seconds.
    public var time: Double
    public var mood: AvatarMoodState
    /// Overrides idle eye wander and turns the body toward it.
    public var gaze: AvatarGaze?
    public var view: AvatarViewRotation?
    /// Freezes body motion and blinking at a calm pose; gaze still applies.
    public var reducedMotion: Bool
    /// What the bot is doing. Nil resolves legacy moods or the state carried by `mood`.
    public var state: AvatarState?
    /// Seconds since the state began. Without it, `done` is drawn at rest.
    public var stateAge: Double?

    public init(
        color: AvatarColor = .defaultBody, eyeColor: AvatarColor = .defaultEyes, time: Double = 0,
        mood: AvatarMoodState = .settled(.neutral), gaze: AvatarGaze? = nil, view: AvatarViewRotation? = nil,
        reducedMotion: Bool = false, state: AvatarState? = nil, stateAge: Double? = nil
    ) {
        self.color = color
        self.eyeColor = eyeColor
        self.time = time
        self.mood = mood
        self.gaze = gaze
        self.view = view
        self.reducedMotion = reducedMotion
        self.state = state
        self.stateAge = stateAge
    }
}

/// One body cross-section or replacement mark, shared by every shape that draws it. `box` bounds it in its own
/// coordinates, before a shape's matrix.
public struct AvatarFramePath: Sendable {
    public var id: String
    public var d: String
    public var segments: [AvatarPathSegment]
    public var evenOdd: Bool
    public var box: AvatarBox
}

/// How one eye is drawn, in its face plane's coordinates (viewBox units).
public enum AvatarEyeMark: Hashable, Sendable {
    /// A filled outline for slits and looks between the pill and happy arc.
    case path(d: String)
    case pill(x: Double, y: Double, width: Double, height: Double, radius: Double)
    /// A quadratic from `start` through `control` to `end`, stroked with round caps.
    case arc(startX: Double, startY: Double, controlX: Double, controlY: Double, endX: Double, endY: Double, strokeWidth: Double)
}

/// Names one cross-section; the same key means the same shape in every frame of an avatar.
public struct AvatarSliceKey: Hashable, Sendable, CustomStringConvertible {
    public var part: Int
    public var sideways: Bool
    public var index: Int

    public var description: String { part < 0 ? "mark-\(index)" : "\(part)\(sideways ? "x" : "z")\(index)" }
}

/// A linear gradient in the ribbon's own coordinates, with evenly spaced color stops.
public struct AvatarRibbonGradient: Hashable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var stops: [AvatarColor]
}

public enum AvatarFrameShape: Sendable {
    case ribbon(index: Int, d: String, box: AvatarBox, matrix: AvatarMatrix, front: Bool, fill: AvatarColor, gradient: AvatarRibbonGradient)
    /// `path` indexes `AvatarFrame.paths`.
    case slice(key: AvatarSliceKey, path: Int, matrix: AvatarMatrix)
    /// `index` is 0 for the left eye, 1 for the right.
    case eye(index: Int, matrix: AvatarMatrix, mark: AvatarEyeMark)

    public var matrix: AvatarMatrix {
        switch self {
        case let .slice(_, _, matrix), let .eye(_, matrix, _), let .ribbon(_, _, _, matrix, _, _, _): matrix
        }
    }
}

/// One frame flattened onto the screen. Painting `shapes` in order (body paths in `color`, eyes in
/// `ink`) inside `root` and a `0 0 100 100` box gives the avatar. Plain numbers, so any vector
/// renderer can draw it.
public struct AvatarFrame: Sendable {
    public var name: String
    public var color: AvatarColor
    public var ink: AvatarColor
    /// Every prepared cross-section, followed by this frame's replacement mark paths.
    /// Prepared indices stay stable across frames; a frame uses only some.
    public var paths: [AvatarFramePath]
    /// 2D motion (hop, roll, squash) about the base. Effect matrices undo it to keep their own placement.
    public var root: AvatarMatrix
    /// Back to front.
    public var shapes: [AvatarFrameShape]
}
