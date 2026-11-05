/// JavaScript `Math.round`: halves go up, also below zero. Output is compared byte for byte with
/// the TypeScript engine, so `.rounded()` (halves away from zero) would not do.
@inline(__always)
func roundHalfUp(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
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
