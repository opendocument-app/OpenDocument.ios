import Foundation

/// What this build links, asked by name rather than by bundle id.
enum Features {

    /// The ad banner and the consent form in front of it: Lite only.
    static var withAds: Bool { LINKS_ADS }

    /// Whether a document shows the ad banner: Lite, until the yearly pass is active.
    static var showsAds: Bool { withAds && !Pass.shared.isActive }

    /// Formatting, paragraph changes and pdf marks: Pro, or Lite with the yearly pass. The Lite
    /// edit screenshot turns them off, because it is taken from the Pro build.
    static var advancedEditing: Bool {
        (ADVANCED_EDITING || Pass.shared.isActive) && ScreenshotMode.screen != .editLite
    }
}
