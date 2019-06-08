/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A document that manages UTF8 text files.
*/

import UIKit

protocol DocumentDelegate: class {
    func documentUpdateContent(_ doc: Document)
    func documentEncrypted(_ doc: Document)
    func documentLoadingError(_ doc: Document)
    func documentLoadingStarted(_ doc: Document)
    func documentLoadingCompleted(_ doc: Document)
    func documentPagesChanged(_ doc: Document)
}

class Document: UIDocument {
    
    public var result: URL?
    public var pageNames: [String]?
    
    public weak var delegate: DocumentDelegate?
    public var loadProgress = Progress(totalUnitCount: 5)
    
    private var page: Int = 0
    private var password: String?
    
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

        var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
        tempPath.appendPathComponent("temp.html")
        
        let core = CoreWrapper()
        core.translate(fileURL.path, into: tempPath.path, at: NSNumber(value: page), with: password)
        
        let errorCode = core.errorCode != nil ? core.errorCode.intValue : 0
        
        if (errorCode == -2) {
            // delay because ViewController might not be visible yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self.delegate?.documentEncrypted(self)
            })
            
            return;
        }
        
        if (errorCode < 0) {
            delegate?.documentLoadingError(self)
            
            return
        }
        
        loadProgress.completedUnitCount = loadProgress.totalUnitCount
        
        var pageNames = [String]()
        for object in core.pageNames {
            if let pageName = object as? String {
                pageNames.append(pageName)
            }
        }
        
        self.pageNames = pageNames
        result = tempPath
        
        delegate?.documentUpdateContent(self)
        
        if (!wasPageCountAnnounced) {
            delegate?.documentPagesChanged(self)
            
            wasPageCountAnnounced = true
        }
        
        delegate?.documentLoadingCompleted(self)
    }
    
    func setPassword(password: String) {
        self.password = password
        
        parse()
    }
    
    func setPage(page: Int) {
        self.page = page
        
        parse()
    }
}

extension Document {
    
    var shortenedDocumentUrl: String {
        return fileURL.absoluteString.prefix(49) + ".." + fileURL.absoluteString.suffix(49)
    }
    
}
