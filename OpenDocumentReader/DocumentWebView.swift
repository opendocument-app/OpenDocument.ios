import WebKit

/// The reader's web view, built with a configuration the app states rather than
/// the one a storyboard hands it.
///
/// A `WKWebViewConfiguration` decoded from a nib arrives with every data
/// detector switched on, and `WKWebView.configuration` returns a copy — so a
/// configuration is only ever settable here, before `super.init`.
///
/// Detectors have to be off. odrcore lays an invisible text layer over a pdf's
/// glyphs for selection and search; iOS finds an address or a date in it, wraps
/// it in a link, and the link's own colour paints that layer over the page the
/// reader is meant to be looking at.
///
/// Nothing the storyboard states about this view is lost by not decoding it:
/// `DocumentViewController` sizes and positions it in code. Its
/// `wkWebViewConfiguration` element stays there and inert — Interface Builder
/// fails to compile the storyboard without one.
final class DocumentWebView: WKWebView {

    required init?(coder: NSCoder) {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        // as the storyboard had it: a document's own media plays without a tap
        configuration.mediaTypesRequiringUserActionForPlayback = []

        super.init(frame: .zero, configuration: configuration)
    }
}
