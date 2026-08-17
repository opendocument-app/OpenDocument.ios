import UIKit

/// The back door the App Store screenshots are taken through.
///
/// `-ODRScreenshot text` puts the app on one screen and leaves it there, so
/// `fastlane snapshot` photographs the same thing in every language without
/// having to drive the document browser - which is Apple's own UI, in eleven
/// languages, and would be a different tap in each.
///
/// Off in every build nobody passes that argument to, and compiled to nothing
/// outside Debug. The documents it opens are bundled the same way: written by
/// `scripts/make-screenshot-documents.py`, and kept out of the archive that
/// goes to the store by `EXCLUDED_SOURCE_FILE_NAMES`.
enum ScreenshotMode {

    /// What one launch shows. The screenshot test launches once per case and
    /// takes one picture, so this list and the one in
    /// `scripts/store-screenshots.py` are the same list.
    enum Screen: String {
        /// the document browser, with one of each format sitting in it
        case browser
        /// an ODF text document, read
        case text
        /// an ODF spreadsheet, with its sheet tabs
        case sheet
        /// the same reader on a Word file
        case office
        /// a pdf with a search under way
        case pdf
        /// a document being edited, keyboard up
        case edit

        /// The sample this screen opens, `nil` where it opens none.
        var sample: String? {
            switch self {
            case .browser: return nil
            case .text, .edit: return "text"
            case .sheet: return "sheet"
            case .office: return "word"
            case .pdf: return "paper"
            }
        }
    }

    /// One entry in the folder, in the order the browser lists them. `source` is
    /// the sample holding its bytes, which only a filler sets.
    struct Sample {
        let name: String
        let format: String
        let source: String

        init(name: String, format: String, from source: String? = nil) {
            self.name = name
            self.format = format
            self.source = source ?? name
        }
    }

    static let folder = [
        Sample(name: "text", format: "odt"),
        Sample(name: "sheet", format: "ods"),
        Sample(name: "slides", format: "odp"),
        Sample(name: "word", format: "docx"),
        Sample(name: "cells", format: "xlsx"),
        Sample(name: "deck", format: "pptx"),
        Sample(name: "paper", format: "pdf"),
        Sample(name: "rows", format: "csv"),
        Sample(name: "notes", format: "txt"),

        // Fillers, so the folder looks like one somebody keeps things in. Each
        // is a copy of a document above under a name of its own, never opened.
        Sample(name: "meeting", format: "odt", from: "text"),
        Sample(name: "letter", format: "odt", from: "text"),
        Sample(name: "travel", format: "odt", from: "text"),
        Sample(name: "reading", format: "odt", from: "text"),
        Sample(name: "household", format: "ods", from: "sheet"),
        Sample(name: "hours", format: "ods", from: "sheet"),
        Sample(name: "stocktake", format: "ods", from: "sheet"),
        Sample(name: "kickoff", format: "odp", from: "slides"),
        Sample(name: "course", format: "odp", from: "slides"),
        Sample(name: "lease", format: "docx", from: "word"),
        Sample(name: "resume", format: "docx", from: "word"),
        Sample(name: "application", format: "docx", from: "word"),
        Sample(name: "expenses", format: "xlsx", from: "cells"),
        Sample(name: "inventory", format: "xlsx", from: "cells"),
        Sample(name: "review", format: "pptx", from: "deck"),
        Sample(name: "ticket", format: "pdf", from: "paper"),
        Sample(name: "warranty", format: "pdf", from: "paper"),
        Sample(name: "manual", format: "pdf", from: "paper"),
    ]

    /// Set on the view the picture is of, once it has something to show. The
    /// test waits for it rather than for a fixed number of seconds, because
    /// translating a document takes as long as the simulator takes.
    static let readyIdentifier = "odr-screenshot-ready"

    /// `nil` unless this launch was asked for a screenshot.
    ///
    /// Read from `UserDefaults` rather than from the argument list, because
    /// `-ODRScreenshot text` on the command line is a default: that is how
    /// XCUITest's `launchArguments` arrive.
    static var screen: Screen? {
        #if DEBUG
            guard let name = UserDefaults.standard.string(forKey: "ODRScreenshot") else { return nil }

            return Screen(rawValue: name)
        #else
            return nil
        #endif
    }

    /// Where each sample ended up, by name, once it was laid out.
    private(set) static var laidOut: [String: URL] = [:]

    /// The browser's own picture, in the order it should reveal them.
    ///
    /// Revealing a document puts it in Recents, which is the tab the browser
    /// opens on, and Recents shows the newest first - so this is back to front.
    static var browserDocuments: [URL] {
        folder.reversed().compactMap { laidOut[$0.name] }
    }

    /// Lays the whole folder out before anything lists it.
    ///
    /// All of it on every screen, not just the one being photographed: the
    /// browser is behind every other picture, and a folder holding one file
    /// looks like a folder nobody uses.
    static func prepare() {
        guard screen != nil else { return }

        empty()

        let details = details()
        query = details?.search ?? ""

        let titles = details?.files ?? [:]
        laidOut = folder.reduce(into: [:]) { found, sample in
            found[sample.name] = layOut(sample, called: titles[sample.name] ?? sample.name)
        }
    }

    /// Clears the folder first. A simulator is kept between runs and between
    /// languages, so without this the picture is this run's documents plus
    /// every run before it, under whatever names those used.
    private static func empty() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let existing = try? FileManager.default.contentsOfDirectory(
                at: documents, includingPropertiesForKeys: nil)
        else {
            return
        }

        for file in existing {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// What the folder is called and what the search screenshot looks for, in
    /// the app's language.
    ///
    /// Written beside the samples by `make-screenshot-documents.py`, because
    /// these are read by nobody but the screenshots and have no business in
    /// `Localizable.strings`.
    private struct Details: Decodable {
        let files: [String: String]
        let search: String
    }

    private static func details() -> Details? {
        guard
            let url = Bundle.main.url(forResource: "screenshot-names", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let all = try? JSONDecoder().decode([String: Details].self, from: data)
        else {
            assertionFailure("no screenshot-names.json bundled - run scripts/make-screenshot-documents.py")

            return nil
        }

        for language in Bundle.main.preferredLocalizations where all[language] != nil {
            return all[language]
        }

        return all["en"]
    }

    /// The word the search screenshot types. Whatever the pdf it is looking at
    /// actually says, which is not always this language.
    private(set) static var query = ""

    /// The sample document of this screen, in the app's language, copied out of
    /// the bundle into the documents directory - which is where the document
    /// browser looks, and the only place the app may write.
    ///
    /// English where the language has no sample of its own, which is what that
    /// storefront's screenshot would show anyway: the app has no UI in it either.
    private static func layOut(_ sample: Sample, called title: String) -> URL? {
        var source: URL?
        for language in Bundle.main.preferredLocalizations + ["en"] {
            source = Bundle.main.url(
                forResource: "sample-\(sample.source)-\(language)", withExtension: sample.format)

            if source != nil { break }
        }

        guard let source else {
            assertionFailure("no \(sample.source) sample bundled - run scripts/make-screenshot-documents.py")

            return nil
        }

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let destination = documents.appendingPathComponent("\(title).\(sample.format)")

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            assertionFailure("could not lay out \(destination.lastPathComponent): \(error)")

            return nil
        }

        return destination
    }

    /// The document this screen opens, once ``prepare()`` has laid it out.
    static func document(for screen: Screen) -> URL? {
        guard let sample = screen.sample else { return nil }

        return laidOut[sample]
    }

    /// Marks the view the test waits for. Does nothing outside a screenshot run.
    static func markReady(_ view: UIView) {
        guard screen != nil else { return }

        view.accessibilityIdentifier = readyIdentifier
    }
}
