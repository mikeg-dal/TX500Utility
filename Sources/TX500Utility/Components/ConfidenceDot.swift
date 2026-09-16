import SwiftUI
import TX500Kit

/// Small colored dot showing how certain a decoded field is.
@MainActor
struct ConfidenceDot: View {
    let confidence: FieldConfidence

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Theme.Metrics.confidenceDotSize, height: Theme.Metrics.confidenceDotSize)
    }

    private var color: Color {
        switch confidence {
        case .confirmed: Theme.Palette.confirmed
        case .inferred: Theme.Palette.inferred
        case .unknown: Theme.Palette.unknown
        }
    }
}
