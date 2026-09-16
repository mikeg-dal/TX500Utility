import SwiftUI

/// The splash logo "filling with water": a dim copy of the logo is the empty glass, and the
/// full-color logo shows through a gently waving water surface that rises with `progress` (0…1).
struct WaterFillLogo: View {
    /// 0 = empty, 1 = full.
    let progress: Double

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate / Theme.Splash.wavePeriod * 2 * .pi
            ZStack {
                logo
                    .saturation(0)
                    .opacity(Theme.Splash.emptyOpacity)
                logo
                    .mask(WaterShape(level: progress, phase: phase, amplitude: Theme.Splash.waveAmplitude))
                    .animation(Theme.Splash.levelAnimation, value: progress)
            }
        }
        .aspectRatio(contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Loading"))
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private var logo: some View {
        SplashImage.logo
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}
