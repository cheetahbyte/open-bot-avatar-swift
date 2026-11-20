/// The per-avatar state a live renderer keeps between frames: the eased look toward a target and
/// the eased change between states and moods. Feed it once per frame.
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
        /// Explicit state wins over the deprecated idle/thinking mood values.
        public var state: AvatarState?

        public init(
            now: Double, mood: AvatarMood = .neutral, target: AvatarLook? = nil, hold: Bool = false,
            reducedMotion: Bool = false, state: AvatarState? = nil
        ) {
            self.now = now
            self.mood = mood
            self.target = target
            self.hold = hold
            self.reducedMotion = reducedMotion
            self.state = state
        }
    }

    public struct Step: Sendable {
        public var gaze: AvatarGaze?
        public var mood: AvatarMoodState
        /// True while the look or a state/mood change is still easing.
        public var moving: Bool
        /// Seconds since the state began; a mood-only change does not restart it.
        public var stateAge: Double
        public var state: AvatarState { mood.state }
    }

    private struct Shown {
        var state: AvatarState
        var mood: AvatarMood
        var from: AvatarMoodState?
        var since: Double
        var began: Double

        func look(at now: Double) -> AvatarMoodState {
            AvatarMoodState(
                state: state, mood: mood, age: now - began, from: from,
                t: AvatarMoodState.progress(elapsed: now - since))
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

        let state = input.state ?? input.mood.defaultState
        let mood = input.mood.resolved
        if let current = shown, state != current.state || mood != current.mood {
            shown = Shown(
                state: state, mood: mood,
                from: input.reducedMotion ? nil : current.look(at: input.now).frozen(),
                since: input.now, began: state == current.state ? current.began : input.now)
        }
        // Mounting done starts at rest, as if its celebration had just finished.
        var current = shown ?? Shown(
            state: state, mood: mood, since: input.now,
            began: input.now - (state == .done ? AvatarPose.doneTurnDuration : 0))
        let t = input.reducedMotion ? 1 : AvatarMoodState.progress(elapsed: input.now - current.since)
        if !(t < 1) { current.from = nil }
        shown = current

        return Step(
            gaze: follow.gaze, mood: current.look(at: input.now), moving: moving || current.from != nil,
            stateAge: input.now - current.began)
    }

    /// Back to rest with no mood history.
    public mutating func reset() {
        self = AvatarAnimator()
    }
}
