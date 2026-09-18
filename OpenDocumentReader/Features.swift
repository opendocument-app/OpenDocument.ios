import Foundation

/// What this build links, asked by name rather than by bundle id.
enum Features {

    /// The ad banner and the consent form in front of it: Lite only.
    static var withAds: Bool { LINKS_ADS }

    /// The editing that goes past typing inside a paragraph: formatting, new
    /// and joined paragraphs, and marks on a pdf. Pro is the build without ads.
    static var advancedEditing: Bool { !LINKS_ADS }
}
