// Generates the document-type resources used by both apps' Info.plists.
// Run from the repository root with: swift scripts/generate-document-icons.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DocumentIcon {
    let name: String
    let color: (CGFloat, CGFloat, CGFloat)
    let paths: [[CGPoint]]
    var finePaths: [[CGPoint]] = []
}

func points(_ coordinates: [CGFloat]) -> [CGPoint] {
    stride(from: 0, to: coordinates.count, by: 2).map {
        CGPoint(x: coordinates[$0], y: coordinates[$0 + 1])
    }
}

let page = points([14, 3, 5, 3, 5, 21, 19, 21, 19, 8, 14, 3, 14, 8, 19, 8])
let icons = [
    DocumentIcon(
        name: "Text", color: (0, 101, 143),
        paths: [
            page, points([8, 12, 16, 12]), points([8, 15, 16, 15]), points([8, 18, 13, 18]),
        ]),
    DocumentIcon(
        name: "Spreadsheet", color: (22, 106, 59),
        paths: [
            points([3, 4, 21, 4, 21, 20, 3, 20, 3, 4]), points([3, 9, 21, 9]),
            points([3, 14.5, 21, 14.5]), points([9, 9, 9, 20]), points([15, 9, 15, 20]),
        ]),
    DocumentIcon(
        name: "Presentation", color: (156, 79, 0),
        paths: [
            points([3, 4, 21, 4, 21, 17, 3, 17, 3, 4]), points([12, 17, 12, 20]),
            points([8, 22, 12, 20, 16, 22]), points([7, 13, 7, 11]),
            points([12, 13, 12, 9]), points([17, 13, 17, 7]),
        ]),
    DocumentIcon(
        name: "PDF", color: (179, 38, 30), paths: [page],
        finePaths: [
            points([7, 16.5, 7, 12, 9, 12, 9, 14.2, 7, 14.2]),
            points([11, 16.5, 11, 12, 12, 12, 13.5, 13, 13.5, 15.5, 12, 16.5, 11, 16.5]),
            points([15.5, 16.5, 15.5, 12, 17.5, 12]), points([15.5, 14.2, 17, 14.2]),
        ]),
]
let output = URL(fileURLWithPath: "OpenDocumentReader/DocumentIcons", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
// The phone and tablet document-icon sizes documented by Apple. Explicit names in the plist
// avoid reliance on asset-catalog lookups by the system's document browser.
for icon in icons {
    for (suffix, width, height) in [("small", 22, 29), ("small@2x", 44, 58), ("64", 64, 64), ("320", 320, 320)] {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let scale = CGFloat(min(width, height)) / 24
        context.translateBy(x: (CGFloat(width) - 24 * scale) / 2, y: (CGFloat(height) + 24 * scale) / 2)
        context.scaleBy(x: scale, y: -scale)
        context.setStrokeColor(
            CGColor(
                red: icon.color.0 / 255, green: icon.color.1 / 255, blue: icon.color.2 / 255, alpha: 1))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for (paths, strokeWidth) in [(icon.paths, CGFloat(1.8)), (icon.finePaths, CGFloat(1.2))] {
            context.setLineWidth(strokeWidth)
            for path in paths {
                context.beginPath()
                context.addLines(between: path)
                context.strokePath()
            }
        }
        let url = output.appendingPathComponent("Document\(icon.name)-\(suffix).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
}
