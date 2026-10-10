import CoreGraphics
import OdrCoreObjC
import UIKit

/// The sheet a document prints on, in points, the unit UIKit prints in.
enum PrintPaper {
    /// Nil where either side is missing or not a length.
    static func size(width: Measure?, height: Measure?) -> CGSize? {
        guard let width, let height,
            let widthPoints = points(width.magnitude, unit: width.unit),
            let heightPoints = points(height.magnitude, unit: height.unit)
        else {
            return nil
        }
        return CGSize(width: widthPoints, height: heightPoints)
    }

    static func points(_ magnitude: Double, unit: String) -> CGFloat? {
        let perUnit: Double
        switch unit {
        case "pt": perUnit = 1
        case "in": perUnit = 72
        case "cm": perUnit = 72 / 2.54
        case "mm": perUnit = 72 / 25.4
        case "pc": perUnit = 12
        case "px": perUnit = 0.75
        default: return nil
        }
        let result = magnitude * perUnit
        return result > 0 ? CGFloat(result) : nil
    }

    /// The first page as a viewer shows it: the crop box, turned by `/Rotate`.
    static func firstPageSize(ofPDFAt url: URL) -> CGSize? {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: 1) else {
            return nil
        }
        let box = page.getBoxRect(.cropBox)
        return page.rotationAngle % 180 == 0
            ? box.size : CGSize(width: box.height, height: box.width)
    }
}

/// Picks the printer's paper for one page size. UIKit takes the size portrait
/// and turns the sheet by `UIPrintInfo.orientation`.
final class PaperChooser: NSObject, UIPrintInteractionControllerDelegate {
    private let pageSize: CGSize

    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }

    var orientation: UIPrintInfo.Orientation {
        pageSize.width > pageSize.height ? .landscape : .portrait
    }

    func printInteractionController(
        _ printInteractionController: UIPrintInteractionController,
        choosePaper paperList: [UIPrintPaper]
    ) -> UIPrintPaper {
        let portrait = CGSize(
            width: min(pageSize.width, pageSize.height),
            height: max(pageSize.width, pageSize.height))
        return UIPrintPaper.bestPaper(forPageSize: portrait, withPapersFrom: paperList)
    }
}
