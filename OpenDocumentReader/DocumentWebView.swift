import WebKit

/// Built here rather than decoded: a nib turns every data detector on, and a
/// configuration cannot be changed once the view has it. Detectors draw links
/// over the invisible text a pdf carries for selection and search.
final class DocumentWebView: WKWebView {

    required init?(coder: NSCoder) {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        configuration.mediaTypesRequiringUserActionForPlayback = []

        super.init(frame: .zero, configuration: configuration)
    }
}
