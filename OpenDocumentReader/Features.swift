import Foundation

/// What this build links, asked by name rather than by bundle id.
enum Features {

    /// The ad banner and the consent form in front of it: Lite only.
    static var withAds: Bool { LINKS_ADS }
}
