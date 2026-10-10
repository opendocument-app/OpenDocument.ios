import WebKit

/// Disable data detectors before creating the web view; their overlays obscure PDF text.
final class DocumentWebView: WKWebView {

    required init?(coder: NSCoder) {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        configuration.mediaTypesRequiringUserActionForPlayback = []

        super.init(frame: .zero, configuration: configuration)
    }
}
