/// JavaScript `Math.round`: halves go up, also below zero. Output is compared byte for byte with
/// the TypeScript engine, so `.rounded()` (halves away from zero) would not do.
@inline(__always)
func roundHalfUp(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}

/// JavaScript's two-coordinate `Math.hypot`: normalize before taking the square root. Its last
/// bit matters when equally distant contour vertices compete to split a simplified loop.
func hypot2(_ x: Double, _ y: Double) -> Double {
    if x.isInfinite || y.isInfinite { return .infinity }
    if x.isNaN || y.isNaN { return .nan }
    let scale = max(abs(x), abs(y))
    if scale == 0 { return 0 }
    let a = abs(x) / scale, b = abs(y) / scale
    return (a * a + b * b).squareRoot() * scale
}

/// JavaScript number formatting for the rounded values serialized here.
func numberText(_ value: Double) -> String {
    if value == 0 { return "0" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
    return value.description
}

func rounded2(_ value: Double) -> String {
    numberText(roundHalfUp(value * 100) / 100)
}

func rounded1(_ value: Double) -> String {
    numberText(roundHalfUp(value * 10) / 10)
}

@inline(__always)
func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, value))
}

@inline(__always)
func smoothstep(_ value: Double) -> Double {
    let x = clamp(value, 0, 1)
    return x * x * (3 - 2 * x)
}

/// `start`, `start + step`, ... below `end`, summed rather than multiplied so the samples match the
/// TypeScript engine's to the last bit.
func accumulatedSamples(from start: Double, to end: Double, by step: Double) -> [Double] {
    var out: [Double] = []
    var value = start
    while value < end {
        out.append(value)
        value += step
    }
    return out
}
