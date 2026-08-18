import UIKit
import WebKit
import XCTest

@testable import OpenDocumentReader

/// Print takes the page the web view is showing, and since odrcore renders a
/// document in the reader's own appearance that page can be dark. Paper is not:
/// a dark page printed as it stands is pale ink on white, which is nothing.
class PrintAppearanceTests: XCTestCase {

    /// The web view prints in light whatever the device is set to, so the menu
    /// needs nothing of its own. This says so, and would say if that changed.
    func testPrintingADarkPageComesOutOnWhitePaper() throws {
        let webview = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))

        // in a window, because that is where a view is told what appearance it
        // is in: a web view on its own stays light whatever is set on it
        let window = UIWindow(frame: webview.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(webview)
        window.makeKeyAndVisible()

        let recorder = NavigationRecorder(finished: expectation(description: "loaded"))
        webview.navigationDelegate = recorder

        // the shape odrcore emits: a dark sheet gated on the reader's preference
        webview.loadHTMLString(
            """
            <html><head><meta name="color-scheme" content="light dark">
            <style media="(prefers-color-scheme: dark)">
            :root{color-scheme:dark}
            body{background:#0d1117;color:#e6edf3}
            </style></head><body><p>Hello</p></body></html>
            """, baseURL: nil)

        wait(for: [recorder.finished], timeout: 30)
        XCTAssertNil(recorder.error)

        // or the rest of this passes without ever having been dark
        XCTAssertEqual(try evaluate("matchMedia('(prefers-color-scheme: dark)').matches", on: webview) as? Bool, true)

        let page = try printFirstPage(of: webview)
        let (mean, darkest) = try brightness(of: page)

        XCTAssertGreaterThan(mean, 0.9, "the paper came out dark")
        XCTAssertLessThan(darkest, 0.3, "nothing dark was printed: the text went white on white")
    }

    private func evaluate(_ script: String, on webview: WKWebView) throws -> Any? {
        var result: Any?
        let done = expectation(description: script)

        webview.evaluateJavaScript(script) { value, error in
            result = value
            XCTAssertNil(error)
            done.fulfill()
        }

        wait(for: [done], timeout: 30)

        return result
    }

    /// One page of what `printDocument` hands the print controller, drawn onto
    /// white the way paper is.
    private func printFirstPage(of webview: WKWebView) throws -> UIImage {
        // US Letter at 72dpi, which is what UIPrintPageRenderer measures in
        let paper = CGRect(x: 0, y: 0, width: 612, height: 792)

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webview.viewPrintFormatter(), startingAtPageAt: 0)
        // the two rects have no setters of their own
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: 36, dy: 36), forKey: "printableRect")

        UIGraphicsBeginImageContextWithOptions(paper.size, true, 1)
        defer { UIGraphicsEndImageContext() }

        UIColor.white.setFill()
        UIRectFill(paper)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        renderer.drawPage(at: 0, in: paper)

        return try XCTUnwrap(UIGraphicsGetImageFromCurrentImageContext())
    }

    private func brightness(of image: UIImage) throws -> (mean: Double, darkest: Double) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        var darkest = 1.0

        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let value =
                (0.299 * Double(pixels[pixel]) + 0.587 * Double(pixels[pixel + 1])
                    + 0.114 * Double(pixels[pixel + 2])) / 255

            total += value
            darkest = min(darkest, value)
        }

        return (total / Double(width * height), darkest)
    }
}
