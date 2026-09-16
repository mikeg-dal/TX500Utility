import AppKit
import SwiftUI

/// Splash artwork bundled with the app (Resources/SplashLogo.png), with a text fallback.
enum SplashImage {
    static var logo: Image {
        if let url = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension),
           let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        return Image(systemName: fallbackSymbol)
    }

    private static let resourceName = "SplashLogo"
    private static let resourceExtension = "png"
    private static let fallbackSymbol = "antenna.radiowaves.left.and.right"
}
