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
    @IBOutlet var controlHeight: NSLayoutConstraint!
    
    var document: UIDocument?
    var initialSelect: Bool = false
    var defaultControlHeight: CGFloat?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        defaultControlHeight = controlHeight.constant
        
        segmentedControl.segmentStyle = .textOnly
        
        segmentedControl.underlineSelected = true
        
        segmentedControl.addTarget(self, action: #selector(DocumentViewController.segmentSelected(sender:)), for: .valueChanged)
        
        openPage(index: 0, refreshSegments: true)
    }
    
    func refreshSegmentedControl(pageCount: Int) {
        for i in 1...pageCount {
            segmentedControl.insertSegment(withTitle: String(i), at: i - 1)
        }
        
        segmentedControl.isHidden = pageCount <= 1
        controlHeight.constant = segmentedControl.isHidden ? 0 : defaultControlHeight!
        
        initialSelect = true
        segmentedControl.selectedSegmentIndex = 0
    }
    
    @objc func segmentSelected(sender:ScrollableSegmentedControl) {
        if (initialSelect) {
            initialSelect = false
            
            return
        }
        
        openPage(index: sender.selectedSegmentIndex, refreshSegments: false)
    }
    
    func openPage(index: Int, refreshSegments: Bool) {
        document?.open(completionHandler: { (success) in
            if success {
                var tempPath = URL(fileURLWithPath: NSTemporaryDirectory())
                tempPath.appendPathComponent("temp.html")
                
                let pageCount = CoreWrapper().translate(self.document?.fileURL.path, into: tempPath.path, at: NSNumber(value: index))
                if (pageCount < 0) {
                    self.webview.loadHTMLString("<html><h1>Error</h1>Failed to load given document. Please try another one while we are working hard to support as many documents as possible. Feel free to contact us via tomtasche@gmail.com for further questions.</html>", baseURL: nil)
                    
                    return
                }
                
                if (refreshSegments) {
                    self.refreshSegmentedControl(pageCount: Int(pageCount))
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
