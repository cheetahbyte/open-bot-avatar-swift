import Foundation

/// Eased look toward a target, stepped once per frame. `attention` fades the whole response in and
/// out, so the eyes and the body's turn hand over to idle motion without a jump.
public struct AvatarFollowState: Hashable, Sendable {
    public var x = 0.0
    public var y = 0.0
    /// 0 is at rest, 1 fully following.
    public var attention = 0.0

    public static let rest = AvatarFollowState()

    /// Look easing, seconds: quick enough to track a moving pointer.
    private static let lookTime = 0.12
    /// Attention moves more slowly, so taking up or losing a target is an unhurried turn.
    private static let attentionTime = 0.3

    public init(x: Double = 0, y: Double = 0, attention: Double = 0) {
        self.x = x
        self.y = y
        self.attention = attention
    }

    /// One frame-rate independent step toward `target` (nil returns to rest). Reduced motion snaps.
    /// Returns whether it still needs frames.
    public mutating func step(toward target: AvatarLook?, deltaTime: Double, reducedMotion: Bool) -> Bool {
        let goal = target.map { AvatarFollowState(x: $0.x, y: $0.y, attention: 1) } ?? .rest
        let dt = max(0, min(deltaTime, 0.1))
        func ease(_ tau: Double) -> Double { reducedMotion ? 1 : 1 - exp(-dt / tau) }
        let k = ease(target != nil ? Self.lookTime : Self.attentionTime)
        let next = AvatarFollowState(
            x: x + (goal.x - x) * k,
            y: y + (goal.y - y) * k,
            attention: attention + (goal.attention - attention) * ease(Self.attentionTime))
        let moving = abs(goal.x - next.x) > 0.002 || abs(goal.y - next.y) > 0.002 || abs(goal.attention - next.attention) > 0.002
        self = moving ? next : goal
        return moving
    }

    /// The pose's look target, nil once at rest. Eased attention is the weight, so the turn starts
    /// and ends gently.
    public var gaze: AvatarGaze? {
        let a = clamp(attention, 0, 1)
        return a > 0 ? AvatarGaze(x: x, y: y, weight: smoothstep(a)) : nil
    }

    /// Small avatars still get a usable reach, points.
    private static let minimumReach = 160.0

    /// Look direction toward a point, from an avatar's box. `origin` is where the look starts, as a
    /// fraction of the box (the eyes). Radial, so diagonals are no stronger than straight lines, and
    /// soft, so it saturates gently beyond about one avatar size.
    public static func look(
        at pointer: (x: Double, y: Double), box: (left: Double, top: Double, width: Double, height: Double),
        origin: (x: Double, y: Double) = (0.5, 0.5)
    ) -> AvatarLook {
        let reach = max(box.width, box.height, minimumReach)
        let dx = (pointer.x - (box.left + box.width * origin.x)) / reach
        let dy = (pointer.y - (box.top + box.height * origin.y)) / reach
        let m = (dx * dx + dy * dy).squareRoot()
        if !m.isFinite || m < 1e-9 { return AvatarLook(x: 0, y: 0) }
        let k = tanh(m) / m
        return AvatarLook(x: dx * k, y: dy * k)
    }
}
