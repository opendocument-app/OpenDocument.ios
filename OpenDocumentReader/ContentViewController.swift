//
//  ContentViewController.swift
//  OpenDocumentReader
//
//  Created by Artsem Lemiasheuski on 17.12.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import UIKit

class ContentViewController: UIViewController {
        
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var subHeaderLabel: UILabel!
    @IBOutlet weak var pageControl: UIPageControl!
    @IBOutlet weak var pageButton: UIButton!
    
    var header = ""
    var subHeader = ""
    var imageFile = ""
    var index = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if traitCollection.userInterfaceStyle == .light {
            pageButton.setTitleColor(#colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1), for: .normal)
            headerLabel.textColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
            subHeaderLabel.textColor = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
            pageControl.currentPageIndicatorTintColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
            pageControl.pageIndicatorTintColor = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
        }
        
        let isLastPage = index == Constants.onboardingImages.count - 1
        pageButton.setTitle(
            NSLocalizedString(isLastPage ? "intro_start" : "intro_next", comment: ""),
            for: .normal)
        
        headerLabel.text = header
        subHeaderLabel.text = subHeader
        imageView.image = UIImage(named: imageFile)
        pageControl.currentPage = index
        pageControl.numberOfPages = Constants.onboardingImages.count
    }
    

    @IBAction func pageButtonPressed(_ sender: Any) {
        switch index {
        case 0, 1:
            (parent as? PageViewController)?.nextVC(atIndex: index)
        case 2:
            dismissViewController()
        default:
            break
        }
    }
    
    @IBAction func skipButtonPressed(_ sender: UIButton) {
        dismissViewController()
    }
    
    func dismissViewController() {
        UserDefaults.standard.set(true, forKey: Constants.key_was_intro_watched)

        dismiss(animated: true, completion: nil)
    }
    
}
