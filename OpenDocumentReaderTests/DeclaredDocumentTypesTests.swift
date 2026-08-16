import OdrCoreObjC
import UniformTypeIdentifiers
import XCTest

@testable import OpenDocumentReader

/// What the app offers itself for, held against odrcore's format table the way
/// OpenDocument.droid holds its manifest against the same table. The plist
/// cannot read the table, so this is what keeps the two from drifting.
class DeclaredDocumentTypesTests: XCTestCase {

    /// Every `LSItemContentTypes` entry of the built app, not of a copy kept
    /// here: the point is to test the plist that ships.
    private lazy var claimed: [UTType] = {
        let bundle = Bundle(for: DocumentViewController.self)
        let entries = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []

        return entries.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }.compactMap { UTType($0) }
    }()

    /// What the app offers itself for: odrcore's document formats, plus the two
    /// non-document ones worth opening a viewer for. Narrower than everything
    /// odrcore translates - it does images, media, fonts and archives too, and
    /// the app does not want to be the handler for an mp3.
    private var offeredFileTypes: [FileType] {
        Odr.allFileTypes.compactMap { FileType(rawValue: $0.intValue) }
            .filter { type in
                guard Odr.capabilities(fileType: type).translateHtml else { return false }

                return Odr.fileCategory(fileType: type) == .document
                    || [.textFile, .commaSeparatedValues].contains(type)
            }
    }

    func testEveryOfferedFormatIsClaimed() {
        for type in offeredFileTypes {
            for fileExtension in Odr.extensions(fileType: type) {
                guard let resolved = UTType(filenameExtension: fileExtension) else {
                    XCTFail("iOS has no type for .\(fileExtension) (\(Odr.string(fileType: type)))")

                    continue
                }

                XCTAssertTrue(
                    claimed.contains(where: resolved.conforms(to:)),
                    ".\(fileExtension) resolves to \(resolved.identifier), which conforms to nothing the app claims")
            }
        }
    }

    /// A dynamic type is what iOS invents for an extension it does not know. It
    /// conforms to `public.data` and nothing else, so a file carrying one is
    /// greyed out in the browser however broad the claims are.
    func testNoOfferedFormatResolvesToADynamicType() {
        for type in offeredFileTypes {
            for fileExtension in Odr.extensions(fileType: type) {
                let resolved = UTType(filenameExtension: fileExtension)

                XCTAssertEqual(
                    resolved?.isDynamic, false,
                    ".\(fileExtension) (\(Odr.string(fileType: type))) needs a UTImportedTypeDeclaration")
            }
        }
    }

    /// The formats odrcore cannot render must not be claimed through one of the
    /// declarations above, or the browser offers a file the app then refuses.
    func testDeclarationsCoverOnlyWhatOdrcoreRenders() throws {
        let declarations =
            Bundle(for: DocumentViewController.self)
            .object(forInfoDictionaryKey: "UTImportedTypeDeclarations") as? [[String: Any]] ?? []

        XCTAssertFalse(declarations.isEmpty)

        for declaration in declarations {
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any] ?? [:]

            for fileExtension in tags["public.filename-extension"] as? [String] ?? [] {
                let type = Odr.fileType(extension: fileExtension)

                XCTAssertTrue(
                    Odr.capabilities(fileType: type).translateHtml,
                    "odrcore does not render .\(fileExtension), so the app must not declare it")
            }
        }
    }
}
