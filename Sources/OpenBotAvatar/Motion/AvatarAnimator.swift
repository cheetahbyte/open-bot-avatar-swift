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

        func state(at now: Double) -> AvatarMoodState {
            from.map { .easing(mood, from: $0, t: AvatarMoodState.progress(elapsed: now - since)) } ?? .settled(mood)
        }
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

        if let current = shown, input.mood != current.mood {
            shown = Shown(mood: input.mood, from: current.state(at: input.now).frozen(), since: input.now)
        }
        var current = shown ?? Shown(mood: input.mood, since: input.now)
        if input.reducedMotion || AvatarMoodState.progress(elapsed: input.now - current.since) >= 1 { current.from = nil }
        shown = current

        return Step(gaze: follow.gaze, mood: current.state(at: input.now), moving: moving || current.from != nil)
    }

    /// Back to rest with no mood history.
    public mutating func reset() {
        self = AvatarAnimator()
    }
}
