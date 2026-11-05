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

    public init(
        color: AvatarColor = .defaultBody, eyeColor: AvatarColor = .defaultEyes, time: Double = 0,
        mood: AvatarMoodState = .settled(.idle), gaze: AvatarGaze? = nil, view: AvatarViewRotation? = nil,
        reducedMotion: Bool = false
    ) {
        self.color = color
        self.eyeColor = eyeColor
        self.time = time
        self.mood = mood
        self.gaze = gaze
        self.view = view
        self.reducedMotion = reducedMotion
    }
}

/// One cross-section outline, shared by every shape that draws it. `box` bounds it in its own
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
    case pill(x: Double, y: Double, width: Double, height: Double, radius: Double)
    /// A quadratic from `start` through `control` to `end`, stroked with round caps.
    case arc(startX: Double, startY: Double, controlX: Double, controlY: Double, endX: Double, endY: Double, strokeWidth: Double)
}

/// Names one cross-section; the same key means the same shape in every frame of an avatar.
public struct AvatarSliceKey: Hashable, Sendable, CustomStringConvertible {
    public var part: Int
    public var sideways: Bool
    public var index: Int

    public var description: String { "\(part)\(sideways ? "x" : "z")\(index)" }
}

public enum AvatarFrameShape: Sendable {
    /// `path` indexes `AvatarFrame.paths`.
    case slice(key: AvatarSliceKey, path: Int, matrix: AvatarMatrix)
    /// `index` is 0 for the left eye, 1 for the right.
    case eye(index: Int, matrix: AvatarMatrix, mark: AvatarEyeMark)

    public var matrix: AvatarMatrix {
        switch self {
        case let .slice(_, _, matrix), let .eye(_, matrix, _): matrix
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
    /// Every cross-section of the avatar. Indices are stable across frames; a frame uses only some.
    public var paths: [AvatarFramePath]
    /// 2D motion (hop, roll, squash) about the base of the body, applied to every shape.
    public var root: AvatarMatrix
    /// Back to front.
    public var shapes: [AvatarFrameShape]
}
