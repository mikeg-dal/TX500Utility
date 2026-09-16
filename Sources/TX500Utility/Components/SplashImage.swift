import AppKit
import SwiftUI

/// Splash artwork bundled with the app (Resources/SplashLogo.png), with a text fallback.
///
/// Deliberately does **not** use `Bundle.module`. That accessor calls `fatalError` when it cannot
/// find its bundle, so a missing image takes the whole app down instead of degrading to the
/// fallback below — which is exactly what happened to a notarised build: the CI toolchain lays the
/// resource bundle out flat (`X.bundle/SplashLogo.png`) while the local one nests it
/// (`X.bundle/Contents/Resources/SplashLogo.png`), `Bundle.module` rejected the flat form, and the
/// app crashed before drawing its first window.
///
/// Searching for the file directly handles both layouts, works under `swift run` where there is no
/// app bundle at all, and cannot crash.
enum SplashImage {
    static var logo: Image {
        if let url = resourceURL, let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        return Image(systemName: fallbackSymbol)
    }

    private static let resourceName = "SplashLogo"
    private static let resourceExtension = "png"
    private static let bundleName = "TX500Utility_TX500Utility.bundle"
    private static let fallbackSymbol = "antenna.radiowaves.left.and.right"

    /// The first place the artwork actually exists, or nil.
    private static let resourceURL: URL? = candidates.first { FileManager.default.fileExists(atPath: $0.path) }

    private static var candidates: [URL] {
        let file = "\(resourceName).\(resourceExtension)"
        var urls: [URL] = []

        // Loose in the app's Resources, if a build ever puts it there.
        if let direct = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) {
            urls.append(direct)
        }

        // Roots that may hold the SwiftPM resource bundle: the app's Resources, the app itself,
        // and the directory holding the executable (which is where `swift run` leaves it).
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())

        for root in roots {
            let bundle = root.appendingPathComponent(bundleName)
            urls.append(bundle.appendingPathComponent(file))                                  // flat
            urls.append(bundle.appendingPathComponent("Contents/Resources").appendingPathComponent(file))
        }
        return urls
    }
}
