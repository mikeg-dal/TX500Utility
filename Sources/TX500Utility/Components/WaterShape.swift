import SwiftUI

/// Filled area below a sine-wave surface. `level` 0 is the bottom edge, 1 the top.
struct WaterShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Keep the wave fully below the top when full and fully hidden when empty.
        let clamped = min(max(level, 0), 1)
        let surfaceY = rect.maxY - (rect.height + amplitude * 2) * clamped + amplitude
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = Int(rect.width / WaterShape.sampleSpacing)
        for i in 0...max(steps, 1) {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(max(steps, 1))
            let angle = Double(x / rect.width) * WaterShape.wavesAcross * 2 * .pi + phase
            path.addLine(to: CGPoint(x: x, y: surfaceY + amplitude * CGFloat(sin(angle))))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// Horizontal distance between wave sample points, in points.
    private static let sampleSpacing: CGFloat = 4
    /// Number of wave crests across the logo.
    private static let wavesAcross = 1.5
}
