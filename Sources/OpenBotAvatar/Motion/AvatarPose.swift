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
    public var eyeShape = AvatarEyeShape.pill

    public struct Input: Sendable {
        public var seed: UInt32
        public var time: Double
        public var mood: AvatarMoodState
        public var gaze: AvatarGaze?
        public var reducedMotion: Bool
        public var view: AvatarViewRotation?

        public init(
            seed: UInt32, time: Double, mood: AvatarMoodState = .settled(.idle), gaze: AvatarGaze? = nil,
            reducedMotion: Bool = false, view: AvatarViewRotation? = nil
        ) {
            self.seed = seed
            self.time = time
            self.mood = mood
            self.gaze = gaze
            self.reducedMotion = reducedMotion
            self.view = view
        }
    }

    public init() {}

    public init(_ input: Input) {
        switch input.mood {
        case let .settled(mood):
            self = Self.moodPose(input, mood)
        case let .easing(mood, from, t):
            let pose = Self.moodPose(input, mood)
            guard t.isFinite, t < 1 else {
                self = pose
                return
            }
            var earlier = input
            earlier.mood = from
            self = Self.blend(AvatarPose(earlier), pose, t)
        }
    }

    /// Part way from `a` to `b`, both taken at the same moment so either side's motion keeps
    /// running. A change of eye shape swaps halfway, inside a blink.
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
        pose.eyeShape = b.eyeShape
        if a.eyeShape != b.eyeShape {
            pose.eyeShape = k < 0.5 ? a.eyeShape : b.eyeShape
            pose.blink = max(pose.blink, 1 - abs(2 * k - 1))
        }
        return pose
    }

    private static func moodPose(_ input: Input, _ mood: AvatarMood) -> AvatarPose {
        let seed = input.seed, reduced = input.reducedMotion
        let tau = Double.pi * 2
        // Slot indices in `AvatarNoise` must fit an Int; this also rejects NaN and infinity.
        let time = abs(input.time) < 1e15 ? input.time : 0
        let t = reduced ? 0 : time + AvatarNoise.value(seed, 7) * 10
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
        switch mood {
        case .happy:
            pose.eyeShape = .happy
            if !reduced {
                let period = 0.92
                let p = ((t.truncatingRemainder(dividingBy: period)) + period).truncatingRemainder(dividingBy: period) / period
                let air = 4 * p * (1 - p)
                let land = clamp(1 - min(p, 1 - p) / 0.12, 0, 1)
                pose.lift = -3.2 * air
                pose.scaleY = 1 - 0.09 * land + 0.03 * air
                pose.scaleX = 1 + 0.07 * land - 0.015 * air
                pose.roll = 4.5 * wave(period * 2)
                pose.yaw += 0.1 * wave(period * 2, 0.6)
            }
        case .thinking:
            pose.yaw += 0.12 + 0.05 * sway * wave(7.3)
            pose.pitch += 0.08
            pose.roll = -5 + 1.4 * wave(4.1)
            pose.lift = -0.5 * (1 - cos(tau * t / 5.2))
            pose.gazeX = 0.55 + 0.3 * wave(5.6)
            pose.gazeY = -0.8
            pose.squintLeft = 0.22
            pose.squintRight = 0.32 + 0.1 * wave(3.1)
            if !reduced { pose.blink = AvatarNoise.blink(seed, t * 0.7) }
        case .idle:
            pose.yaw += 0.07 * sway * wave(6.1)
            pose.pitch += 0.04 * sway * wave(4.7, 1)
            pose.roll = 1.6 * wave(5.3, 2)
            pose.lift = -0.45 * (1 - cos(tau * t / 3.4))
            let breath = wave(3.4, -.pi / 2)
            pose.scaleY = 1 + 0.012 * breath
            pose.scaleX = 1 - 0.008 * breath
            if !reduced {
                pose.blink = AvatarNoise.blink(seed, t)
                (pose.gazeX, pose.gazeY) = AvatarNoise.wander(seed, t)
            }
        }

        if let given, weight > 0 {
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * weight }
            let share = reduced ? 1 : lookEyes
            if pose.eyeShape == .pill {
                pose.gazeX = mix(pose.gazeX, given.x * share)
                pose.gazeY = mix(pose.gazeY, given.y * share)
            }
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
