import Foundation

/// What this build links, asked by name rather than by bundle id.
enum Features {

    /// The ad banner and the consent form in front of it: Lite only.
    static var withAds: Bool { LINKS_ADS }

    /// Formatting, paragraph changes and pdf marks: Pro only. The Lite edit
    /// screenshot turns them off, because it is taken from the Pro build.
    static var advancedEditing: Bool { ADVANCED_EDITING && ScreenshotMode.screen != .editLite }
}
