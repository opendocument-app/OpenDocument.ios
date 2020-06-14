//
//  PageViewController.swift
//  OpenDocumentReader
//
//  Created by Artsem Lemiasheuski on 17.12.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import UIKit

class PageViewController: UIPageViewController {
    
    let contentViewController = "contentViewController"
    
    var headersArray = [NSLocalizedString("intro_title_open", comment: ""),
                        NSLocalizedString("intro_title_edit", comment: ""),
                        NSLocalizedString("intro_title_apps", comment: ""),]
    var subHeadersArray = [NSLocalizedString("intro_description_open", comment: ""),
                           NSLocalizedString("intro_description_edit", comment: ""),
                           NSLocalizedString("intro_description_apps", comment: ""),]
    var imagesArray = [Constants.onboarding_image_1,
                       Constants.onboarding_image_2,
                       Constants.onboarding_image_3]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.dataSource = self
        
        if let firstVC = displayViewController(at: 0) {
            setViewControllers([firstVC], direction: .forward, animated: true, completion: nil)
        }
    }
    
    func displayViewController(at index: Int) -> ContentViewController? {
        guard index < headersArray.count && index >= 0 else { return nil }
        guard let contentVC =
            storyboard?.instantiateViewController(withIdentifier: contentViewController) as? ContentViewController else { return nil }
        
        contentVC.imageFile = imagesArray[index]
        contentVC.header = headersArray[index]
        contentVC.subHeader = subHeadersArray[index]
        contentVC.index = index
        
        return contentVC
    }
    
    func nextVC(atIndex index: Int) {
        if let contentVC = displayViewController(at: index + 1) {
            setViewControllers([contentVC], direction: .forward, animated: true, completion: nil)
        }
    }
}

extension PageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        var index = (viewController as! ContentViewController).index
        index -= 1

        return displayViewController(at: index)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        var index = (viewController as! ContentViewController).index
        index += 1

        return displayViewController(at: index)
    }
}
