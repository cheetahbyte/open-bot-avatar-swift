import Foundation

/// Floating-point sRGB, retained until the final conversion to `AvatarColor` so interpolation
/// matches color.ts rather than interpolating already-rounded bytes.
struct AvatarRGB: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: AvatarColor) {
        self.init(red: Double(color.red), green: Double(color.green), blue: Double(color.blue))
    }

    var color: AvatarColor {
        func byte(_ value: Double) -> UInt8 { UInt8(roundHalfUp(clamp(value, 0, 255))) }
        return AvatarColor(red: byte(red), green: byte(green), blue: byte(blue))
    }

    func mixed(with other: AvatarRGB, by t: Double) -> AvatarRGB {
        AvatarRGB(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t)
    }

    /// Darken toward a deeper, slightly more saturated color, not gray-black.
    func shaded(by t: Double) -> AvatarRGB {
        let peak = max(red, green, blue)
        let deep = AvatarRGB(
            red: red * 0.35 - (peak - red) * 0.1,
            green: green * 0.35 - (peak - green) * 0.1,
            blue: blue * 0.35 - (peak - blue) * 0.1)
        return mixed(with: deep, by: t)
    }

    func tinted(by t: Double) -> AvatarRGB {
        mixed(with: AvatarRGB(red: 255, green: 255, blue: 255), by: t)
    }

    /// WCAG relative luminance (the upstream threshold is deliberately 0.03928).
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            let s = value / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrast(with other: AvatarRGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static let darkInk = AvatarRGB(red: 20, green: 22, blue: 34)
    static let lightInk = AvatarRGB(red: 250, green: 250, blue: 255)

    var autoEyeColor: AvatarRGB {
        contrast(with: Self.darkInk) >= contrast(with: Self.lightInk) ? Self.darkInk : Self.lightInk
    }

    /// Lightness 0...1, chroma, and hue in degrees.
    var oklch: (lightness: Double, chroma: Double, hue: Double) {
        func linear(_ value: Double) -> Double {
            let s = value / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let light = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        let hue = atan2(bb, a) * 180 / .pi
        return (light, hypot(a, bb), hue < 0 ? hue + 360 : hue)
    }

    /// Preserve lightness and hue, lowering chroma by a 20-step bisection only if out of gamut.
    static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double) -> AvatarRGB {
        func linear(_ c: Double) -> (Double, Double, Double) {
            let a = c * cos(hue * .pi / 180), b = c * sin(hue * .pi / 180)
            let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(lightness - 0.0894841775 * a - 1.291485548 * b, 3)
            return (
                4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)
        }
        func fits(_ c: Double) -> Bool {
            let (r, g, b) = linear(c)
            return [r, g, b].allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 }
        }
        var lo = 0.0, hi = chroma
        if !fits(hi) {
            for _ in 0..<20 {
                let mid = (lo + hi) / 2
                if fits(mid) { lo = mid } else { hi = mid }
            }
            hi = lo
        }
        func fromLinear(_ value: Double) -> Double {
            255 * (value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055)
        }
        let (r, g, b) = linear(hi)
        return AvatarRGB(red: fromLinear(r), green: fromLinear(g), blue: fromLinear(b))
    }
}

/// One ribbon's five tail-to-head stops, still in floating-point sRGB.
struct RibbonColorRun: Sendable {
    fileprivate var stops: [AvatarRGB]
}

/// The color at `t` along a run, interpolated in sRGB and then rounded to bytes.
func runAt(_ run: RibbonColorRun, _ t: Double) -> AvatarColor {
    let x = clamp(t, 0, 1) * Double(run.stops.count - 1)
    let n = min(Int(floor(x)), run.stops.count - 2)
    return run.stops[n].mixed(with: run.stops[n + 1], by: x - Double(n)).color
}

private let rampLight = 0.09
private let rampHue = 14.0
private let rampRange = (0.36, 0.9)
private let warm = 100.0
private let gradientLight = 0.13
private let gradientHue = 25.0
private let gradientStops = 5
private let neutralThreshold = 0.04
private let neutralTint = 0.025
private let bandShades = [[0, 1, 2], [2, 0, 3], [1, 2, 0]]

private func turnToward(_ hue: Double, _ to: Double, _ by: Double) -> Double {
    let d = (to - hue + 540).truncatingRemainder(dividingBy: 360) - 180
    let sign = d == 0 ? 0.0 : d < 0 ? -1.0 : 1.0
    return (hue + sign * min(abs(d), by) + 360).truncatingRemainder(dividingBy: 360)
}

/// All mutable state is protected by `lock`; color calculation never holds it.
private final class RibbonPaletteCache: @unchecked Sendable {
    private struct Key: Hashable {
        var color: AvatarColor
        var seed: UInt32
    }

    private let lock = NSLock()
    private var entries: [Key: [RibbonColorRun]] = [:]

    func palette(_ color: AvatarColor, seed: UInt32) -> [RibbonColorRun] {
        let key = Key(color: color, seed: seed)
        if let hit = lock.withLock({ entries[key] }) { return hit }
        let palette = makeRibbonPalette(color, seed: seed)
        return lock.withLock {
            // Another caller may have finished this same calculation in the meantime.
            if let hit = entries[key] { return hit }
            if entries.count >= 64 { entries.removeAll(keepingCapacity: true) }
            entries[key] = palette
            return palette
        }
    }
}

private let paletteCache = RibbonPaletteCache()

/// The nine hoop/lane runs in upstream order; working turns use the first three to five.
/// Memoized by resolved body color and seed, with upstream's clear-at-64 policy.
func ribbonPalette(_ color: AvatarColor?, seed: UInt32) -> [RibbonColorRun] {
    paletteCache.palette(color ?? .defaultBody, seed: seed)
}

private func makeRibbonPalette(_ color: AvatarColor, seed: UInt32) -> [RibbonColorRun] {
    let (light, chroma, hue) = AvatarRGB(color).oklch
    let neutral = chroma < neutralThreshold
    let base = neutral ? (130 + AvatarNoise.value(seed, 500) * 310).truncatingRemainder(dividingBy: 360) : hue
    let c = neutral ? neutralTint : max(chroma, 0.17)
    let from = clamp(light, rampRange.0, rampRange.1)
    var steps: [Int] = []
    for k in 1..<10 {
        if steps.count >= 5 { break }
        for step in [k, -k] {
            let l = from + Double(step) * rampLight
            if steps.count < 5 && l >= rampRange.0 - 1e-9 && l <= rampRange.1 + 1e-9 { steps.append(step) }
        }
    }
    while steps.count < 5 { steps.append(steps.last ?? 1) }
    let shades = steps.map { step -> (step: Int, run: RibbonColorRun) in
        let l = from + Double(step) * rampLight
        let h = turnToward(base, step > 0 ? warm : warm + 180, rampHue * Double(abs(step)))
        let away = step > 0 ? 1.0 : -1.0
        let run = (0..<gradientStops).map { n in
            let t = Double(n) / Double(gradientStops - 1)
            let hue = turnToward(h, away > 0 ? warm : warm + 180, gradientHue * t)
            return AvatarRGB.oklch(clamp(l + away * gradientLight * t, 0.26, 0.9), c, hue)
        }
        return (step, RibbonColorRun(stops: run))
    }
    return bandShades.flatMap { pick in
        pick.map { shades[$0] }.sorted { $0.step > $1.step }.map(\.run)
    }
}
