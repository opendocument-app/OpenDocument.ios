import Foundation
import XCTest

/// The hand-off to `fastlane snapshot`, which is a directory and a file name.
///
/// Nothing is passed in process. `capture_ios_screenshots` writes what the run
/// is for into a cache directory on the host, launches this bundle once per
/// language, and afterwards collects whatever PNGs it finds there. That is the
/// whole protocol: two files read, one directory written.
///
/// fastlane ships a `SnapshotHelper.swift` to do this, and it used to sit here
/// verbatim - three hundred lines carrying macOS, tvOS and watchOS branches, a
/// landscape correction, and a wait on the network activity indicator that iOS
/// has not drawn since 13. None of it applied to this app, and none of it could
/// be read or formatted like the rest of these sources, because a copied file
/// has to stay byte for byte theirs to be replaceable. This is the part we use,
/// written as ours.
///
/// One thing theirs does that this does not: it passes on the `launch_arguments`
/// from the lane, through a third file. The lane sets none, and the app takes
/// the only argument it cares about from ``ScreenshotTests`` directly.
///
/// https://docs.fastlane.tools/actions/snapshot/
enum Snapshots {

    /// Where fastlane leaves what it wants, and looks for what it gets back.
    /// Absent off a simulator, which is the one place this cannot run.
    private static var handOff: URL? {
        guard let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
            return nil
        }

        return URL(fileURLWithPath: host).appendingPathComponent("Library/Caches/tools.fastlane")
    }

    private static var pictures: URL? {
        handOff?.appendingPathComponent("screenshots", isDirectory: true)
    }

    /// Puts the language and region this run is for on the app's arguments.
    ///
    /// One launch of this bundle is one language. The app cannot work out which
    /// on its own - the simulator is the same one every time - so fastlane names
    /// it in a file and it is handed over here.
    @MainActor
    static func prepare(_ app: XCUIApplication) {
        guard let handOff else {
            XCTFail("no SIMULATOR_HOST_HOME: screenshots are taken on a simulator, by fastlane")

            return
        }

        let language = read(handOff.appendingPathComponent("language.txt"))
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }

        // The region decides how a date and a number are written, which is half
        // of what a spreadsheet screenshot shows. It follows the language when
        // the lane does not name one of its own.
        let region =
            read(handOff.appendingPathComponent("locale.txt"))
            ?? language.map { Locale(identifier: $0).identifier }
        if let region {
            app.launchArguments += ["-AppleLocale", "\"\(region)\""]
        }
    }

    /// Writes the screen under the name the release expects to find.
    ///
    /// `scripts/store-screenshots.py` reads these back by name, so the shape of
    /// it - the device, then the screen - is a promise to that script.
    @MainActor
    static func take(_ name: String) {
        guard let pictures,
            let simulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
        else {
            XCTFail("nowhere to write \(name): fastlane did not set this run up")

            return
        }

        // whatever is still easing into place, which no element can be waited on
        // for - the tab bar settling, a keyboard finishing its way up
        Thread.sleep(forTimeInterval: 0.5)

        let file = pictures.appendingPathComponent("\(model(of: simulator))-\(name).png")

        do {
            try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: file, options: .atomic)
        } catch {
            XCTFail("could not write \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// The model's own name. xcodebuild calls a device "Clone 2 of iPhone 17 Pro
    /// Max" when it runs several at once, and the release expects the plain one.
    private static func model(of simulator: String) -> String {
        guard simulator.hasPrefix("Clone "), let of = simulator.range(of: " of ") else {
            return simulator
        }

        return String(simulator[of.upperBound...])
    }

    /// A line fastlane left, or `nil` where it left nothing to say.
    private static func read(_ file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return line.isEmpty ? nil : line
    }
}
