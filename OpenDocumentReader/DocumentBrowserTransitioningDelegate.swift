/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A transitioning delegate that animates segues for a document browser.
*/

import UIKit

/// - Tag: DocumentBrowserTransitioningDelegate
class DocumentBrowserTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    
    let transitionController: UIDocumentBrowserTransitionController
    
    init(withTransitionController transitionController: UIDocumentBrowserTransitionController) {
        self.transitionController = transitionController
    }
    
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return transitionController
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return transitionController
    }
}
