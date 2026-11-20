import Foundation

/// A look target, each axis -1...1 (x right, y down).
public struct AvatarLook: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A look target with its share of the pose: `weight` 0...1 fades it in over the idle motion, so
/// following can start and stop without a jump.
public struct AvatarGaze: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var weight: Double

    public init(x: Double, y: Double, weight: Double = 1) {
        self.x = x
        self.y = y
        self.weight = weight
    }
}

/// Extra rotation in radians on top of the resting view: yaw turns left and right, pitch tips.
public struct AvatarViewRotation: Hashable, Sendable {
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }
}

public enum AvatarEyeShape: Hashable, Sendable {
    case pill, happy
}

/// Numeric eye shapes mix continuously; the remaining share is the plain pill.
public struct AvatarEyeLook: Hashable, Sendable {
    public var arc: Double
    public var slit: Double

    public init(arc: Double = 0, slit: Double = 0) {
        self.arc = arc
        self.slit = slit
    }
}

/// A deterministic pose: a pure function of its input, with no wall clock or randomness, so any
/// frame can be reproduced exactly.
public struct AvatarPose: Hashable, Sendable {
    /// Resting view: turned a little and seen a little from above.
    public static let baseYaw = -0.3
    public static let basePitch = 0.2
    /// Following a target, the body turns by up to these angles and the eyes use this share of
    /// their small range, so the whole character looks rather than the eyes sliding alone.
    static let lookYaw = 0.32
    static let lookPitch = 0.18
    static let lookEyes = 0.7
    /// Bounds on the motion: the hop, and the share of a point's distance from the base that roll
    /// and squash can move it. `PreparedAvatar.extent` relies on them.
    static let maxLift = 4.0
    static let maxSway = 0.2

    public var yaw = baseYaw
    public var pitch = basePitch
    /// Degrees.
    public var roll = 0.0
    /// Negative is up, viewBox units.
    public var lift = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    public var gazeX = 0.0
    public var gazeY = 0.0
    /// 0 is open, 1 fully closed.
    public var blink = 0.0
    public var squintLeft = 0.0
    public var squintRight = 0.0
    public var eyes = AvatarEyeLook()
    public var ribbons = 0.0
    public var cage = 0.0
    public var sweep = 0.0
    public var bang = 0.0
    public var dots = 0.0

    /// Compatibility view of the eye look. Use `eyes` to retain intermediate shapes.
    @available(*, deprecated, message: "Use eyes.arc and eyes.slit for morphing eye shapes.")
    public var eyeShape: AvatarEyeShape {
        get { eyes.arc >= 0.5 ? .happy : .pill }
        set { eyes = AvatarEyeLook(arc: newValue == .happy ? 1 : 0) }
    }

    public struct Input: Sendable {
        public var seed: UInt32
        public var time: Double
        public var mood: AvatarMoodState
        public var gaze: AvatarGaze?
        public var reducedMotion: Bool
        public var view: AvatarViewRotation?
        public var state: AvatarState?
        /// Seconds since the state began. Without it `done` is at rest.
        public var stateAge: Double?

        public init(
            seed: UInt32, time: Double, mood: AvatarMoodState = .settled(.neutral), gaze: AvatarGaze? = nil,
            reducedMotion: Bool = false, view: AvatarViewRotation? = nil,
            state: AvatarState? = nil, stateAge: Double? = nil
        ) {
            self.seed = seed
            self.time = time
            self.mood = mood
            self.gaze = gaze
            self.reducedMotion = reducedMotion
            self.view = view
            self.state = state
            self.stateAge = stateAge
        }
    }

    public init() {}

    public init(_ input: Input) {
        let state = input.state ?? input.mood.state
        let pose = Self.statePose(input, state: state, mood: input.mood.mood.resolved)
        guard let blend = input.mood.blend, blend.t < 1 else {
            self = pose
            return
        }
        var earlier = input
        earlier.state = blend.from.state
        earlier.mood = blend.from
        // Mood-only changes keep the state's clock running on both sides. A state that was left
        // is held at the age it had when the change began.
        earlier.stateAge = blend.from.state == state ? input.stateAge : blend.from.age
        self = Self.blend(AvatarPose(earlier), pose, blend.t.isFinite ? blend.t : 1)
    }

    /// Part way from `a` to `b`, both taken at the same moment so either side's motion keeps
    /// running. Eye shapes morph continuously; ribbons retain the emitting side's turn and layout.
    public static func blend(_ a: AvatarPose, _ b: AvatarPose, _ t: Double) -> AvatarPose {
        let k = clamp(t, 0, 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * k }
        var pose = AvatarPose()
        pose.yaw = mix(a.yaw, b.yaw)
        pose.pitch = mix(a.pitch, b.pitch)
        pose.roll = mix(a.roll, b.roll)
        pose.lift = mix(a.lift, b.lift)
        pose.scaleX = mix(a.scaleX, b.scaleX)
        pose.scaleY = mix(a.scaleY, b.scaleY)
        pose.gazeX = mix(a.gazeX, b.gazeX)
        pose.gazeY = mix(a.gazeY, b.gazeY)
        pose.blink = mix(a.blink, b.blink)
        pose.squintLeft = mix(a.squintLeft, b.squintLeft)
        pose.squintRight = mix(a.squintRight, b.squintRight)
        pose.eyes = AvatarEyeLook(arc: mix(a.eyes.arc, b.eyes.arc), slit: mix(a.eyes.slit, b.eyes.slit))
        pose.ribbons = mix(a.ribbons, b.ribbons)
        pose.cage = a.ribbons > 0 && b.ribbons > 0 ? mix(a.cage, b.cage) : a.ribbons > 0 ? a.cage : b.cage
        pose.sweep = a.ribbons > 0 && b.ribbons > 0 ? mix(a.sweep, b.sweep) : a.ribbons > 0 ? a.sweep : b.sweep
        pose.bang = mix(a.bang, b.bang)
        pose.dots = mix(a.dots, b.dots)
        return pose
    }

    public static let doneTurnDuration = 3.87
    public static let doneCycleDuration = 6.2
    private static let workTurnDuration = 1.5

    /// Seconds into a working turn, or nil between turns.
    private static func workTurn(_ seed: UInt32, _ age: Double) -> Double? {
        let first = 1.2 + 1.2 * AvatarNoise.value(seed, 41)
        if age < first { return nil }
        let n = ((age - first) / 7.5).rounded(.down)
        for k in [n, n - 1] where k >= 0 {
            let start = first + k * 7.5 + (k != 0 ? 1.5 * AvatarNoise.value(seed, 60 + k) : 0)
            if age >= start && age < start + workTurnDuration { return age - start }
        }
        return nil
    }

    /// The celebration's measured wind-up, steady run and slow-down, in ribbon radians.
    private static func celebration(_ t: Double) -> Double {
        let tau = Double.pi * 2
        let speed = (9 * tau + 0.5) / 2.4625
        if t <= 0 { return 0 }
        if t < 0.24 { return -0.25 * (1 - cos(.pi * t / 0.24)) }
        if t < 0.54 { return -0.5 + speed * pow(t - 0.24, 2) / 0.6 }
        if t < 2.54 { return -0.5 + speed * (t - 0.39) }
        if t < 3.79 { return -0.5 + speed * 2.15 + 1.25 * speed * (1 - pow(1 - (t - 2.54) / 1.25, 4)) / 4 }
        return 9 * tau
    }

    private static func statePose(_ input: Input, state: AvatarState, mood: AvatarMood) -> AvatarPose {
        let seed = input.seed, reduced = input.reducedMotion
        let tau = Double.pi * 2
        let time = input.time
        let t = reduced ? 0 : time + AvatarNoise.value(seed, 7) * 10
        let live = reduced ? 0.0 : 1.0
        func wave(_ period: Double, _ phase: Double = 0) -> Double {
            reduced ? 0 : sin(tau * t / period + phase)
        }
        var given: (x: Double, y: Double)?
        var weight = 0.0
        if let gaze = input.gaze, gaze.x.isFinite, gaze.y.isFinite {
            given = (clamp(gaze.x, -1, 1), clamp(gaze.y, -1, 1))
            weight = gaze.weight.isFinite ? clamp(gaze.weight, 0, 1) : 1
        }
        let sway = 1 - 0.7 * weight
        var pose = AvatarPose()
        pose.eyes.arc = mood == .happy ? 1 : 0

        func rest(_ pace: Double) {
            pose.yaw += 0.07 * sway * wave(6.1 * pace)
            pose.pitch += 0.04 * sway * wave(4.7 * pace, 1)
            pose.roll = 1.6 * wave(5.3 * pace, 2)
            pose.lift = reduced ? 0 : -0.45 * (1 - cos(tau * t / (3.4 * pace)))
            let breath = wave(3.4 * pace, -.pi / 2)
            pose.scaleY = 1 + 0.012 * breath
            pose.scaleX = 1 - 0.008 * breath
            if !reduced {
                pose.blink = AvatarNoise.blink(seed, t)
                (pose.gazeX, pose.gazeY) = AvatarNoise.wander(seed, t)
            }
        }

        if state == .idle && mood == .happy {
            let period = 0.92
            let p = reduced ? 0.5 : ((t.truncatingRemainder(dividingBy: period)) + period).truncatingRemainder(dividingBy: period) / period
            let air = 4 * p * (1 - p)
            let land = reduced ? 0 : clamp(1 - min(p, 1 - p) / 0.12, 0, 1)
            pose.lift = reduced ? 0 : -3.2 * air
            pose.scaleY = 1 - 0.09 * land + 0.03 * air * live
            pose.scaleX = 1 + 0.07 * land - 0.015 * air * live
            pose.roll = 4.5 * wave(period * 2)
            pose.yaw += 0.1 * wave(period * 2, 0.6)
        } else if state == .thinking {
            pose.yaw += 0.12 + 0.05 * sway * wave(7.3)
            pose.pitch += 0.08
            pose.roll = -5 + 1.4 * wave(4.1)
            pose.lift = -0.5 * (1 - cos(tau * t / 5.2)) * live
            pose.gazeX = 0.55 + 0.3 * wave(5.6)
            pose.gazeY = -0.8
            pose.squintLeft = 0.22
            pose.squintRight = 0.32 + 0.1 * wave(3.1)
            if !reduced { pose.blink = AvatarNoise.blink(seed, t * 0.7) }
            pose.dots = 1
        } else if state == .working {
            let beat = wave(0.7)
            pose.yaw += 0.08 * sway * wave(2.3, 0.4)
            pose.pitch -= 0.05
            pose.roll = 3 + 0.6 * beat
            pose.lift = -0.3 * (0.5 + 0.5 * beat) * live
            pose.scaleY = 0.99 - 0.008 * beat
            pose.scaleX = 1.005 + 0.005 * beat
            pose.squintLeft = 0.25
            pose.squintRight = 0.25
            if reduced {
                pose.gazeX = 0.15
                pose.gazeY = 0.3
            } else {
                (pose.gazeX, pose.gazeY) = AvatarNoise.dart(seed, t)
                pose.blink = AvatarNoise.blink(seed, t * 1.3)
            }
            let age = input.stateAge.flatMap { $0.isFinite ? max(0, $0) : nil } ?? max(0, time)
            if let into = reduced ? nil : workTurn(seed, age) {
                let e = 6.2 * into
                let turn = tau * (1 - (1 + e) * exp(-e))
                let swell = sin(turn / 2)
                pose.ribbons = clamp(into / 0.16, 0, 1) * clamp((workTurnDuration - into) / 0.5, 0, 1)
                pose.sweep = turn
                pose.yaw += 0.22 * swell
                pose.roll += 3 * swell
                pose.lift -= 1.2 * swell
                pose.gazeX = clamp(pose.gazeX * (1 - swell) - 0.85 * sin(turn), -1, 1)
                pose.gazeY = pose.gazeY * (1 - swell) - 0.3 * swell
            }
        } else if state == .waiting {
            let p = reduced ? 0 : ((t.truncatingRemainder(dividingBy: 6.5)) + 6.5).truncatingRemainder(dividingBy: 6.5) / 6.5
            let sigh = sin(tau * clamp(p / 0.33, 0, 1))
            pose.yaw += 0.04 * sway * wave(7.4)
            pose.pitch += 0.02 + 0.03 * sigh
            pose.roll = 7 + 1.2 * wave(6.4, 2)
            pose.lift = -0.3 * (1 - cos(tau * t / 6.5)) * live
            pose.scaleY = 1 + 0.025 * sigh
            pose.scaleX = 1 - 0.012 * sigh
            pose.gazeX = 0.5 + 0.15 * wave(8.2)
            pose.gazeY = 0.1
            pose.eyes.slit = 1 - pose.eyes.arc
            if !reduced { pose.blink = AvatarNoise.blink(seed, t * 0.6) }
        } else if state == .blocked {
            pose.scaleY = 1.02
            pose.scaleX = 0.99
            pose.bang = 1
        } else if state == .done {
            rest(1.25)
            let age = !reduced ? input.stateAge.flatMap { $0.isFinite ? max(0, $0) : nil } ?? doneTurnDuration : doneTurnDuration
            let length = doneCycleDuration * (1 + 0.15 * AvatarNoise.value(seed, 31))
            let cycle = (age / length).rounded(.down), since = age - cycle * length
            if since < doneTurnDuration {
                let swell = sin(.pi * since / doneTurnDuration)
                let way = cycle.truncatingRemainder(dividingBy: 2) != 0 ? -1.0 : 1.0
                let sweep = celebration(since) * way
                let angle = sweep / 3
                // JavaScript Math.round chooses +infinity at a tie, including negative angles.
                pose.yaw += angle - tau * floor(angle / tau + 0.5)
                pose.lift -= 2.2 * swell
                pose.scaleY += 0.04 * swell
                pose.ribbons = clamp(since / 0.1, 0, 1) * clamp((doneTurnDuration - since) / 0.5, 0, 1)
                pose.cage = 1
                pose.sweep = way * max(0, celebration(since))
            }
        } else {
            rest(1)
        }

        if let given, weight > 0 {
            let share = reduced ? 1 : lookEyes
            let follow = weight * (1 - pose.eyes.arc)
            pose.gazeX += (given.x * share - pose.gazeX) * follow
            pose.gazeY += (given.y * share - pose.gazeY) * follow
            if !reduced {
                pose.yaw += weight * (given.x * lookYaw - baseYaw)
                pose.pitch += weight * (-given.y * lookPitch - basePitch / 2)
            }
        }
        if let view = input.view, view.yaw.isFinite, view.pitch.isFinite {
            pose.yaw += view.yaw
            pose.pitch += view.pitch
        }
        return pose
    }
}
