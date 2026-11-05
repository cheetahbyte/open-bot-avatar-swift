import Foundation

/// Seeded, stateless motion noise. Ids are hashed as UTF-16, like the TypeScript engine.
public enum AvatarNoise {
    public static func hash(_ string: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for unit in string.utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        return h
    }

    /// In [0, 1).
    static func value(_ seed: UInt32, _ n: Int) -> Double {
        var h = seed ^ (UInt32(truncatingIfNeeded: n) &* 0x9E37_79B1)
        h = (h ^ (h >> 16)) &* 0x85EB_CA6B
        h = (h ^ (h >> 13)) &* 0xC2B2_AE35
        h ^= h >> 16
        return Double(h) / 4_294_967_296
    }

    /// Closure 0...1: one blink per ~4.2 s slot at a seeded offset, sometimes a double blink.
    static func blink(_ seed: UInt32, _ t: Double) -> Double {
        let slotLength = 4.2, duration = 0.19
        let slot = Int((t / slotLength).rounded(.down))
        var closure = 0.0
        for s in [slot - 1, slot] {
            let start = Double(s) * slotLength + 0.5 + value(seed, s * 2) * 2.9
            let starts = value(seed, s * 2 + 1) > 0.8 ? [start, start + 0.34] : [start]
            for b in starts {
                let u = (t - b) / duration
                if u > 0 && u < 1 { closure = max(closure, sin(.pi * u)) }
            }
        }
        return closure
    }

    /// Idle eye wander: short holds between quick saccades, centered more often than not.
    static func wander(_ seed: UInt32, _ t: Double) -> (Double, Double) {
        let slotLength = 1.9
        let s = Int((t / slotLength).rounded(.down))
        func target(_ k: Int) -> (Double, Double) {
            if value(seed, 1000 + k * 3) < 0.4 { return (0, 0) }
            return ((value(seed, 1001 + k * 3) * 2 - 1) * 0.6, (value(seed, 1002 + k * 3) * 2 - 1) * 0.35)
        }
        let a = target(s - 1), b = target(s)
        let e = smoothstep((t - Double(s) * slotLength) / 0.16)
        return (a.0 + (b.0 - a.0) * e, a.1 + (b.1 - a.1) * e)
    }
}
