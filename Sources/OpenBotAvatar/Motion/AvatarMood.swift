/// What the avatar is doing, independently of how it feels.
public enum AvatarState: String, CaseIterable, Codable, Sendable {
    case idle, thinking, working, waiting, blocked, done
}

public enum AvatarMood: String, CaseIterable, Codable, Sendable {
    case neutral, happy

    @available(*, deprecated, message: "Use AvatarState.idle and AvatarMood.neutral.")
    case idle
    @available(*, deprecated, message: "Use AvatarState.thinking and AvatarMood.neutral.")
    case thinking

    public static let allCases: [AvatarMood] = [.neutral, .happy]

    var defaultState: AvatarState { rawValue == "thinking" ? .thinking : .idle }
    var resolved: AvatarMood { self == .happy ? .happy : .neutral }
}

/// A mood on screen, possibly still easing in over what was shown before it.
public indirect enum AvatarMoodState: Hashable, Sendable {
    case settled(AvatarMood)
    /// `mood` easing in from `from`, at eased progress `t` 0...1.
    case easing(AvatarMood, from: AvatarMoodState, t: Double)
    /// State, mood and the age at which a state was left. Nil age leaves `done` at rest.
    case settledState(state: AvatarState, mood: AvatarMood, age: Double?)
    case easingState(state: AvatarState, mood: AvatarMood, age: Double?, from: AvatarMoodState, t: Double)

    public init(
        state: AvatarState? = nil, mood: AvatarMood = .neutral, age: Double? = nil,
        from: AvatarMoodState? = nil, t: Double = 1
    ) {
        let state = state ?? mood.defaultState
        if let from {
            self = .easingState(state: state, mood: mood.resolved, age: age, from: from, t: t)
        } else {
            self = .settledState(state: state, mood: mood.resolved, age: age)
        }
    }

    /// Length of a mood change, seconds.
    public static let changeDuration = 0.42

    public var mood: AvatarMood {
        switch self {
        case let .settled(mood), let .easing(mood, _, _): mood
        case let .settledState(_, mood, _), let .easingState(_, mood, _, _, _): mood
        }
    }

    public var state: AvatarState {
        switch self {
        case .settled, .easing: mood.defaultState
        case let .settledState(state, _, _), let .easingState(state, _, _, _, _): state
        }
    }

    public var age: Double? {
        switch self {
        case .settled, .easing: nil
        case let .settledState(_, _, age), let .easingState(_, _, age, _, _): age
        }
    }

    /// The frozen earlier look and eased progress, if a change is under way.
    public var blend: (from: AvatarMoodState, t: Double)? {
        switch self {
        case .settled, .settledState: nil
        case let .easing(_, from, t), let .easingState(_, _, _, from, t): (from, t)
        }
    }

    /// Eased progress of a mood change from elapsed seconds.
    public static func progress(elapsed: Double) -> Double {
        smoothstep(elapsed / changeDuration)
    }

    /// What a new change eases in from: this state with any change under way frozen at its progress.
    /// Older changes whose share has all but faded (or beyond a few levels) are dropped, so rapid
    /// changes never grow the chain.
    public func frozen() -> AvatarMoodState {
        frozen(share: 1, depth: 0)
    }

    private func frozen(share: Double, depth: Int) -> AvatarMoodState {
        guard let blend else { return self }
        let rest = share * (1 - blend.t)
        let drop = rest < 0.02 || depth >= 3
        switch self {
        case let .easing(mood, from, t):
            return drop ? .settled(mood) : .easing(mood, from: from.frozen(share: rest, depth: depth + 1), t: t)
        case let .easingState(state, mood, age, from, t):
            return drop ? .settledState(state: state, mood: mood, age: age)
                : .easingState(state: state, mood: mood, age: age, from: from.frozen(share: rest, depth: depth + 1), t: t)
        case .settled, .settledState:
            return self
        }
    }
}
