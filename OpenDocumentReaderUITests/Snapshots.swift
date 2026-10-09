import Foundation
import XCTest

/// Read fastlane language and locale files and write simulator screenshots.
/// Launch arguments are set by ScreenshotTests. See https://docs.fastlane.tools/actions/snapshot/.
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

    /// Pass fastlane language and locale settings to the app.
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

        // Use the language as the locale fallback for dates and numbers.
        let region =
            read(handOff.appendingPathComponent("locale.txt"))
            ?? language.map { Locale(identifier: $0).identifier }
        if let region {
            app.launchArguments += ["-AppleLocale", "\"\(region)\""]
        }
    }

    /// Write <device>-<screen>.png for scripts/store_screenshots.py.
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
