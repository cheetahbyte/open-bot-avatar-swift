/// The per-avatar state a live renderer keeps between frames: the eased look toward a target and
/// the eased change between moods. Feed it once per frame.
public struct AvatarAnimator: Sendable {
    public struct Input: Sendable {
        /// Wall clock, seconds. Easing runs on it even when the animation clock stops.
        public var now: Double
        public var mood: AvatarMood
        /// Nil eases back to rest.
        public var target: AvatarLook?
        /// Keep the current look as it is, for example while the user drags the view.
        public var hold: Bool
        /// Snap instead of easing.
        public var reducedMotion: Bool

        public init(now: Double, mood: AvatarMood, target: AvatarLook? = nil, hold: Bool = false, reducedMotion: Bool = false) {
            self.now = now
            self.mood = mood
            self.target = target
            self.hold = hold
            self.reducedMotion = reducedMotion
        }
    }

    public struct Step: Sendable {
        public var gaze: AvatarGaze?
        public var mood: AvatarMoodState
        /// True while the look or a mood change is still easing.
        public var moving: Bool
    }

    private struct Shown {
        var mood: AvatarMood
        var from: AvatarMoodState?
        var since: Double
    }

    private var follow = AvatarFollowState.rest
    private var last: Double?
    private var shown: Shown?

    public init() {}

    public mutating func step(_ input: Input) -> Step {
        let dt = last.map { input.now - $0 } ?? 0
        last = input.now
        var moving = false
        if !input.hold {
            moving = follow.step(toward: input.target, deltaTime: dt, reducedMotion: input.reducedMotion)
        }

        // A new mood eases in from the pose on screen, a change under way included.
        if let current = shown, input.mood != current.mood {
            let state = current.from.map {
                AvatarMoodState.easing(current.mood, from: $0, t: AvatarMoodState.progress(elapsed: input.now - current.since))
            } ?? .settled(current.mood)
            shown = Shown(mood: input.mood, from: input.reducedMotion ? nil : state.frozen(), since: input.now)
        }
        var current = shown ?? Shown(mood: input.mood, since: input.now)
        let t = input.reducedMotion ? 1 : AvatarMoodState.progress(elapsed: input.now - current.since)
        var mood = AvatarMoodState.settled(current.mood)
        if let from = current.from, t < 1 {
            mood = .easing(current.mood, from: from, t: t)
        } else {
            current.from = nil
        }
        shown = current

        var easing = false
        if case .easing = mood { easing = true }
        return Step(gaze: follow.gaze, mood: mood, moving: moving || easing)
    }

    /// Back to rest with no mood history.
    public mutating func reset() {
        self = AvatarAnimator()
    }
}
