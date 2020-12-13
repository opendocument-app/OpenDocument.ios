//
//  OpenDocumentReaderTests.swift
//  OpenDocumentReaderTests
//
//  Created by Thomas Taschauer on 08.11.20.
//  Copyright © 2020 Thomas Taschauer. All rights reserved.
//

import XCTest

@testable import OpenDocumentReader

class OpenDocumentReaderTests: XCTestCase {
    
    private var saveURL: URL?

    override func setUpWithError() throws {
        let url = URL(string: "https://api.libreoffice.org/examples/cpp/DocumentLoader/test.odt")
        
        let documentsURL = try
            FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
        
        saveURL = documentsURL.appendingPathComponent(url!.lastPathComponent)
        
        if (FileManager.default.fileExists(atPath: saveURL!.path)) {
            return
        }
        
        var fileURL: URL?
        
        let downloadTask = URLSession.shared.downloadTask(with: url!) {
            urlOrNil, responseOrNil, errorOrNil in
            
            fileURL = urlOrNil
        }
        downloadTask.resume()
        
        try FileManager.default.moveItem(at: fileURL!, to: self.saveURL!)
    }
    
    func testExample() throws {
        measure {
            let coreWrapper = CoreWrapper()
                            
            var translatePath = URL(fileURLWithPath: NSTemporaryDirectory())
            translatePath.appendPathComponent("translate.html")
            
            coreWrapper.translate(saveURL?.path, into: translatePath.path, at: 0, with: nil, editable: true)
            XCTAssertNil(coreWrapper.errorCode)
            
            var backTranslatePath = URL(fileURLWithPath: NSTemporaryDirectory())
            backTranslatePath.appendPathComponent("backtranslate.html")
            
            let diff = "{\"modifiedText\":{\"3\":\"This is a simple test document to demonstrate the DocumentLoadewwwwr example!\"}}"
            
            coreWrapper.backTranslate(diff, into: backTranslatePath.path)
            XCTAssertNil(coreWrapper.errorCode)
        }
    }
}
