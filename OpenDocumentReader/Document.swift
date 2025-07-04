import UIKit
import WebKit
import FirebaseCrashlytics

protocol DocumentDelegate: class {
    func documentUpdateContent(_ doc: Document)
    func documentEncrypted(_ doc: Document)
    func documentLoadingError(_ doc: Document, errorCode: Int)
    func documentLoadingStarted(_ doc: Document)
    func documentLoadingCompleted(_ doc: Document)
    func documentPagesChanged(_ doc: Document)
}

enum DocumentError: Error {
    case getHtml
    case backTranslate
}


class Document: UIDocument {
    
    public var result: URL?
    public var pageNames: [String]?
    public var pagePaths: [String]?

    public weak var delegate: DocumentDelegate?
    public var loadProgress = Progress(totalUnitCount: 5)
    
    private var saveGroup = DispatchGroup()
    private var coreWrapper = CoreWrapper()
    
    public var page: Int = 0 {
        didSet {
            parse()
        }
    }
    public var password: String? {
        didSet {
            parse()
        }
    }
    public var edit = false {
        didSet {
            parse()
        }
    }
    
    public var webview: WKWebView?
    
    public var isOdf = false
    private var wasPageCountAnnounced = false
    
    override init(fileURL url: URL) {
        super.init(fileURL: url)
    }
    
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        parse()
    }
    
    func parse() {
        delegate?.documentLoadingStarted(self)
        
        loadProgress.completedUnitCount = 2
        loadProgress.resume()
        
        result = nil
        delegate?.documentUpdateContent(self)

        let cachePath = URL(fileURLWithPath: NSTemporaryDirectory())
        let outputPath = URL(fileURLWithPath: NSTemporaryDirectory())
        coreWrapper.translate(fileURL.path, cache: cachePath.path, into: outputPath.path, with: password, editable: edit)

        let errorCode = coreWrapper.errorCode != nil ? coreWrapper.errorCode.intValue : 0
        if (errorCode == -2) {
            self.delegate?.documentEncrypted(self)
            
            return
        }
        
        if (errorCode < 0) {
            delegate?.documentLoadingError(self, errorCode: errorCode)
            
            return
        }
        
        isOdf = true
        
        loadProgress.completedUnitCount = loadProgress.totalUnitCount
        
        var pageNames = [String]()
        for object in coreWrapper.pageNames {
            if let pageName = object as? String {
                pageNames.append(pageName)
            }
        }
        
        var pagePaths = [String]()
        for object in coreWrapper.pagePaths {
            if let pagePath = object as? String {
                pagePaths.append(pagePath)
            }
        }
        
        self.pagePaths = pagePaths
        self.pageNames = pageNames
        
        // TODO: use all pages instead of just one!
        result = URL(fileURLWithPath: pagePaths[page])
        
        delegate?.documentUpdateContent(self)
        
        if (!wasPageCountAnnounced) {
            delegate?.documentPagesChanged(self)
            
            wasPageCountAnnounced = true
        }
        
        delegate?.documentLoadingCompleted(self)
    }
    
    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        Crashlytics.crashlytics().record(error: error)
    }
    
    override func writeContents(_ contents: Any, to url: URL, for saveOperation: UIDocument.SaveOperation, originalContentsURL: URL?) throws {
        var diff = ""

        DispatchQueue.main.sync {
            self.saveGroup.enter()

            webview?.evaluateJavaScript("odr.generateDiff()", completionHandler: { (value: Any!, error: Error!) -> Void in
                if error != nil {
                    Crashlytics.crashlytics().record(error: error)
                    fatalError("generateDiff failed")

                    return
                }
                
                diff = (value as? String)!

                self.saveGroup.leave()
            })
        }
        
        let waitResult = saveGroup.wait(timeout: .now() + 30)
        if (waitResult != DispatchTimeoutResult.success) {
            throw DocumentError.getHtml
        }
        
        // running on main-thread to make sure CoreWrapper is always called from the same thread
        // TODO: run on background thread instead?
        DispatchQueue.main.sync {
            coreWrapper.backTranslate(diff, into: url.path)
        }
        
        let errorCode = coreWrapper.errorCode != nil ? coreWrapper.errorCode.intValue : 0
        if (errorCode < 0) {
            print(errorCode)
            
            throw DocumentError.backTranslate
        }
    }
}

extension Document {
    
    var shortenedDocumentUrl: String {
        return fileURL.absoluteString.prefix(49) + ".." + fileURL.absoluteString.suffix(49)
    }
}
