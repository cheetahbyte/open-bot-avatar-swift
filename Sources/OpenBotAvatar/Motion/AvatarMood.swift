public enum AvatarMood: String, CaseIterable, Codable, Sendable {
    case idle, thinking, happy
}

/// A mood on screen, possibly still easing in over what was shown before it.
public indirect enum AvatarMoodState: Hashable, Sendable {
    case settled(AvatarMood)
    /// `mood` easing in from `from`, at eased progress `t` 0...1.
    case easing(AvatarMood, from: AvatarMoodState, t: Double)

    /// Length of a mood change, seconds.
    public static let changeDuration = 0.42

    public var mood: AvatarMood {
        switch self {
        case let .settled(mood), let .easing(mood, _, _): mood
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
        guard case let .easing(mood, from, t) = self else { return self }
        let rest = share * (1 - t)
        if rest < 0.02 || depth >= 3 { return .settled(mood) }
        return .easing(mood, from: from.frozen(share: rest, depth: depth + 1), t: t)
    }
}
