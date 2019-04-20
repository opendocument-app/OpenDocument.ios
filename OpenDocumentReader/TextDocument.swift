/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A document that manages UTF8 text files.
*/

import UIKit

protocol TextDocumentDelegate: class {
    func textDocumentUpdateContent(_ doc: TextDocument)
    func textDocumentEncrypted(_ doc: TextDocument)
    func textDocumentLoadingError(_ doc: TextDocument)
    func textDocumentLoadingStarted(_ doc: TextDocument)
    func textDocumentLoadingCompleted(_ doc: TextDocument)
}

/// - Tag: TextDocument
class TextDocument: UIDocument {
    
    public var result: URL?
    
    public weak var delegate: TextDocumentDelegate?
    public var loadProgress = Progress(totalUnitCount: 1)
    
    private var page: Int = 0
    private var password: String?
    
    override init(fileURL url: URL) {
        super.init(fileURL: url)
    }
    
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        parse()
    }
    
    func parse() {
        delegate?.textDocumentLoadingStarted(self)
        
        loadProgress.completedUnitCount = 0
        loadProgress.resume()
        
        result = nil
        delegate?.textDocumentUpdateContent(self)
        
        var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
        tempPath.appendPathComponent("temp.html")
        
        let pageCount = CoreWrapper().translate(fileURL.path, into: tempPath.path, at: NSNumber(value: page), with: password)
        
        if (pageCount == -2) {
            // delay because ViewController might not be visible yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self.delegate?.textDocumentEncrypted(self)
            })
            
            return;
        }
        
        if (pageCount < 0) {
            delegate?.textDocumentLoadingError(self)
            
            return
        }
        
        //        if (refreshSegments) {
        //            self.refreshSegmentedControl(pageCount: Int(pageCount))
        //        }
        
        loadProgress.completedUnitCount = loadProgress.totalUnitCount
        
        result = tempPath
        delegate?.textDocumentUpdateContent(self)
        delegate?.textDocumentLoadingCompleted(self)
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
