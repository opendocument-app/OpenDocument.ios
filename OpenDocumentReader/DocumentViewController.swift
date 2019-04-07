//
//  DocumentViewController.swift
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 06.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import UIKit
import WebKit
import ScrollableSegmentedControl

class DocumentViewController: UIViewController {
    
    @IBOutlet weak var webview: WKWebView!
    @IBOutlet weak var segmentedControl: ScrollableSegmentedControl!
    
    var document: UIDocument?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        segmentedControl.segmentStyle = .textOnly
        segmentedControl.insertSegment(withTitle: "1", at: 0)
        segmentedControl.insertSegment(withTitle: "2", at: 1)
        segmentedControl.insertSegment(withTitle: "3", at: 2)
        segmentedControl.insertSegment(withTitle: "4", at: 3)
        segmentedControl.insertSegment(withTitle: "5", at: 4)
        segmentedControl.insertSegment(withTitle: "6", at: 5)
        
        segmentedControl.underlineSelected = true
        segmentedControl.selectedSegmentIndex = 0
        
        segmentedControl.addTarget(self, action: #selector(DocumentViewController.segmentSelected(sender:)), for: .valueChanged)
        
        openPage(index: 0)
    }
    
    @objc func segmentSelected(sender:ScrollableSegmentedControl) {
        openPage(index: sender.selectedSegmentIndex)
        print("Segment at index \(sender.selectedSegmentIndex)  selected")
    }
    
    func openPage(index: Int) {
        document?.open(completionHandler: { (success) in
            if success {
                var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
                tempPath.appendPathComponent("temp.html")
                
                let translateSuccess = CoreWrapper().translate(self.document?.fileURL.path, into: tempPath.path, at: NSNumber(value: index))
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
