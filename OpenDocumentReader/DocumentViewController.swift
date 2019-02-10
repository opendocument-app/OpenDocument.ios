//
//  DocumentViewController.swift
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 06.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import UIKit
import WebKit

class DocumentViewController: UIViewController {
    
    @IBOutlet weak var webview: WKWebView!
    
    var document: UIDocument?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Access the document
        document?.open(completionHandler: { (success) in
            if success {
                var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
                tempPath.appendPathComponent("temp.html")
                
                let translateSuccess = CoreWrapper().translate(self.document?.fileURL.path, into: tempPath.path)
                if (!translateSuccess) {
                    self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document. Please try another one while we are working hard to support as many documents as possible. Feel free to contact us via tomtasche@gmail.com for further questions.</html>", baseURL: nil)
                    
                    return
                }
                
                self.webview.loadFileURL(tempPath, allowingReadAccessTo: tempPath)
            } else {
                // Make sure to handle the failed import appropriately, e.g., by presenting an error message to the user.
            }
        })
    }
    
    @IBAction func dismissDocumentViewController() {
        dismiss(animated: true) {
            self.document?.close(completionHandler: nil)
        }
    }
}
