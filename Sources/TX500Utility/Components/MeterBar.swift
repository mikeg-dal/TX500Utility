import SwiftUI

/// Horizontal bar meter with green → yellow → red zones.
@MainActor
struct MeterBar: View {
    /// Current reading.
    let value: Double
    /// Full-scale reading.
    let maximum: Double

    private var fraction: Double { maximum > 0 ? min(max(value / maximum, 0), 1) : 0 }

    private var fillColor: Color {
        switch fraction {
        case Theme.MeterZones.high...: Theme.Palette.meterHigh
        case Theme.MeterZones.mid...: Theme.Palette.meterMid
        default: Theme.Palette.meterLow
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.meterTrack)
                Capsule()
                    .fill(fillColor)
                    .frame(width: geo.size.width * fraction)
                    .animation(Theme.Motion.quick, value: fraction)
            }
        }
        .frame(height: Theme.Metrics.meterHeight)
        .frame(maxWidth: Theme.Metrics.meterWidth)
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
