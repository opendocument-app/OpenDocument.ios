import UIKit

/// Apple deprecated the app-delegate-only life cycle with the iOS 26 SDK, so
/// window and URL handling live here now instead of in AppDelegate.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let url = connectionOptions.urlContexts.first?.url else { return }

        // the storyboard's root view controller is not wired up yet at this point
        DispatchQueue.main.async {
            self.open(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

        open(url)
    }

    /// Documents handed to us by other apps land in Documents/Inbox, which the
    /// document browser does not show, so they get moved up one level first.
    private func open(_ inputURL: URL) {
        guard let documentBrowserViewController = window?.rootViewController as? DocumentBrowserViewController else {
            CrashManager.shared.log("root view controller is not a DocumentBrowserViewController")

            return
        }

        guard let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            CrashManager.shared.log("no documents directory")

            return
        }

        let destinationUrl: URL
        do {
            destinationUrl = try Self.importFromInbox(inputURL, documents: documentsUrl)
        } catch {
            CrashManager.shared.log(error)
            documentBrowserViewController.showGenericError()
            return
        }

        documentBrowserViewController.revealDocument(at: destinationUrl, importIfNeeded: true) {
            revealedDocumentURL, error in
            guard let documentUrl = revealedDocumentURL else {
                if let error { CrashManager.shared.log(error) }
                documentBrowserViewController.showGenericError()
                return
            }

            documentBrowserViewController.presentDocument(at: documentUrl)
        }
    }

    /// Move Inbox files into Documents without replacing an existing file.
    static func importFromInbox(_ input: URL, documents: URL) throws -> URL {
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL
        guard input.isFileURL, input.deletingLastPathComponent().standardizedFileURL == inbox else {
            return input
        }

        let manager = FileManager.default
        let name = input.deletingPathExtension().lastPathComponent
        let suffix = input.pathExtension.isEmpty ? "" : "." + input.pathExtension
        var destination = documents.appendingPathComponent(input.lastPathComponent)
        var number = 2
        while manager.fileExists(atPath: destination.path) {
            destination = documents.appendingPathComponent("\(name) (\(number))\(suffix)")
            number += 1
        }

        try manager.moveItem(at: input, to: destination)
        return destination
    }
}
