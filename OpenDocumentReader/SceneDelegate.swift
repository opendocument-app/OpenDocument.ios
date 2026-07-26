import UIKit

/// Apple deprecated the app-delegate-only life cycle with the iOS 26 SDK, so
/// window and URL handling live here now instead of in AppDelegate.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
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

        let inboxUrl = documentsUrl.appendingPathComponent("Inbox")

        let destinationUrl: URL
        if inputURL.absoluteString.contains(inboxUrl.absoluteString) {
            destinationUrl = documentsUrl.appendingPathComponent(inputURL.lastPathComponent)

            do {
                try FileManager.default.moveItem(at: inputURL, to: destinationUrl)
            } catch {
                CrashManager.shared.log(error)

                return
            }
        } else {
            destinationUrl = inputURL
        }

        documentBrowserViewController.revealDocument(at: destinationUrl, importIfNeeded: true) { revealedDocumentURL, _ in
            guard let documentUrl = revealedDocumentURL else {
                // ignoring errors because they should pop up in failedToImportDocumentAt too

                return
            }

            documentBrowserViewController.presentDocument(at: documentUrl)
        }
    }
}
