import SwiftUI

/// Single source of truth for visual styling. Views never use literal sizes, colors or fonts;
/// they reference these tokens. Change the look of the whole app here.
enum Theme {

    // MARK: Spacing (4-pt scale)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Shape

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    enum Stroke {
        static let hairline: CGFloat = 1
    }

    // MARK: Typography

    enum Typography {
        static let frequency = Font.system(size: 44, weight: .semibold, design: .monospaced)
        static let frequencySecondary = Font.system(.title3, design: .monospaced)
        static let value = Font.system(.title3, design: .rounded).weight(.medium)
        static let label = Font.caption.weight(.medium)
        static let sectionTitle = Font.headline
        static let body = Font.body
        static let mono = Font.system(.body, design: .monospaced)
        static let monoSmall = Font.system(.caption, design: .monospaced)
        static let badge = Font.caption2.weight(.bold)
    }

    // MARK: Color (semantic; adapts to light/dark automatically)

    enum Palette {
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let cardBorder = Color(nsColor: .separatorColor)
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let accent = Color.accentColor

        static let receive = Color.green
        static let transmit = Color.red
        static let warning = Color.orange
        static let danger = Color.red
        static let success = Color.green
        static let inactive = Color.gray

        static let meterTrack = Color(nsColor: .quaternaryLabelColor)
        static let meterLow = Color.green
        static let meterMid = Color.yellow
        static let meterHigh = Color.red

        /// Backup source badges.
        static let sourceRadio = Color.accentColor
        static let sourceImported = Color.purple

        /// Function badges: lit when the function is on.
        static let badgeOn = Color.accentColor
        static let badgeOff = Color.gray

        /// Settings viewer.
        static let cellChanged = Color.orange
        static let cellDecoded = Color.accentColor
        static let gridHeader = Color(nsColor: .underPageBackgroundColor)
        static let confirmed = Color.green
        static let inferred = Color.yellow
        static let unknown = Color.gray
    }

    enum Opacity {
        /// Tinted backgrounds behind badges and banners.
        static let tint = 0.12
        static let disabled = 0.4
        /// Background for "off" function badges so they recede.
        static let badgeOff = 0.35
        /// Fill behind changed / decoded spreadsheet cells.
        static let cellHighlight = 0.3
        static let cellDecodedTint = 0.08
    }

    /// Fractions of full scale where meters change color.
    enum MeterZones {
        static let mid = 0.6
        static let high = 0.85
    }

    // MARK: Component metrics

    enum Metrics {
        static let meterHeight: CGFloat = 10
        static let meterWidth: CGFloat = 320
        static let statusDotSize: CGFloat = 8
        static let sidebarMinWidth: CGFloat = 180
        /// Window floor. Below this, badges and button text start getting squeezed. Every fixed
        /// width in the app is sized to fit inside it: at 750 the usable width in a card is
        /// 750 - 180 sidebar - 48 page padding - 32 card padding = 490pt.
        static let contentMinWidth: CGFloat = 750
        static let contentMinHeight: CGFloat = 675
        /// Usable width inside a card at the minimum window size, for sizing fixed columns.
        static let cardContentWidthAtMinimum: CGFloat = 490
        static let fieldWidth: CGFloat = 160
        /// Memory table columns. The table is a LazyVStack rather than a Grid so that 100 rows are
        /// not all built at once, which means the columns need explicit widths.
        static let memoryChannelWidth: CGFloat = 44
        static let memoryFrequencyWidth: CGFloat = 130
        static let memoryModeWidth: CGFloat = 96
        static let memoryPreAttWidth: CGFloat = 96
        static let memoryClearWidth: CGFloat = 24
        /// Logo at the foot of the sidebar; fits the 180pt sidebar with margins.
        static let brandingWidth: CGFloat = 132
        static let portPickerMaxWidth: CGFloat = 260
        static let consoleMinHeight: CGFloat = 200
        static let gridCellWidth: CGFloat = 34
        static let gridRowHeaderWidth: CGFloat = 96
        static let gridCellHeight: CGFloat = 22
        static let viewerMinWidth: CGFloat = 900
        static let viewerMinHeight: CGFloat = 600
        static let confidenceDotSize: CGFloat = 6
        static let preferencesWidth: CGFloat = 520
        static let sheetWidth: CGFloat = 560
        static let surveySheetWidth: CGFloat = 760
        static let surveySheetMinHeight: CGFloat = 520
        static let sheetMinHeight: CGFloat = 360
        static let unitFieldWidth: CGFloat = 80
        static let connectionProgressWidth: CGFloat = 80
    }

    // MARK: Splash / loading screen

    enum Splash {
        static let background = Color(red: 0.10, green: 0.106, blue: 0.122)   // matches the Lab599 artwork
        static let text = Color.white
        static let secondaryText = Color.white.opacity(0.55)
        static let accent = Color(red: 0.84, green: 0.05, blue: 0.20)          // Lab599 red
        static let logoWidth: CGFloat = 420
        static let progressWidth: CGFloat = 360
        static let stepIconWidth: CGFloat = 18
        /// Opacity of the "empty glass" logo.
        static let emptyOpacity = 0.18
        /// Height of the water surface wave, in points.
        static let waveAmplitude: CGFloat = 6
        /// Seconds per wave cycle.
        static let wavePeriod: TimeInterval = 2.2
        static let levelAnimation = Animation.easeInOut(duration: 0.6)
        static let fadeAnimation = Animation.easeInOut(duration: 0.35)
    }

    // MARK: Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let standard = Animation.easeInOut(duration: 0.25)
    }
}
