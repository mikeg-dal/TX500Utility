import Foundation

/// Linear mapping between a raw CAT value and the value the radio shows on its screen.
public struct LevelScale: Sendable, Hashable {
    public let rawRange: ClosedRange<Int>
    public let displayRange: ClosedRange<Int>
    public let unit: String
    /// How the radio turns a fractional display value into the whole number it shows.
    public let rounding: FloatingPointRoundingRule

    public init(rawRange: ClosedRange<Int>, displayRange: ClosedRange<Int>, unit: String,
                rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) {
        self.rawRange = rawRange
        self.displayRange = displayRange
        self.unit = unit
        self.rounding = rounding
    }

    private var rawSpan: Double { Double(rawRange.upperBound - rawRange.lowerBound) }
    private var displaySpan: Double { Double(displayRange.upperBound - displayRange.lowerBound) }

    /// Raw CAT value → front-panel value, clamped to the display range.
    public func display(fromRaw raw: Int) -> Int {
        let clamped = min(max(raw, rawRange.lowerBound), rawRange.upperBound)
        let fraction = Double(clamped - rawRange.lowerBound) / rawSpan
        return displayRange.lowerBound + Int((fraction * displaySpan).rounded(rounding))
    }

    /// Front-panel value → raw CAT value, clamped to the raw range.
    /// Picks the raw value the radio will show as exactly `value` (inverse of the rounding rule).
    public func raw(fromDisplay value: Int) -> Int {
        let clamped = min(max(value, displayRange.lowerBound), displayRange.upperBound)
        let fraction = Double(clamped - displayRange.lowerBound) / displaySpan
        let inverse: FloatingPointRoundingRule = rounding == .down ? .up : rounding
        return min(rawRange.lowerBound + Int((fraction * rawSpan).rounded(inverse)), rawRange.upperBound)
    }

    /// Raw steps per displayed unit, rounded up (RF gain 101 raw over 57 dB → 2).
    public var rawPerDisplayUnit: Int { Int((rawSpan / displaySpan).rounded(.up)) }

    /// e.g. "50 %", "−3 dB", "120 CPM", "68".
    public func formatted(_ value: Int) -> String {
        unit.isEmpty ? String(value) : "\(value) \(unit)"
    }
}
