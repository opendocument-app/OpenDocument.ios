//
//  AppDelegate.swift
//  OpenDocument Reader
//
//  Created by Thomas Taschauer on 06.02.19.
//  Copyright © 2019 Thomas Taschauer. All rights reserved.
//

import UIKit
import Firebase
import Adjust

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        if ConfigurationManager.manager.configuration == .lite {
            let filePath = Bundle.main.path(forResource: "GoogleService-Info-Lite", ofType: "plist")!
            let options = FirebaseOptions(contentsOfFile: filePath)
            FirebaseApp.configure(options: options!)
        } else {
            FirebaseApp.configure()
        }
        
        StoreReviewHelper.incrementAppOpenedCount()
        
        let adjustKey = Bundle.main.object(forInfoDictionaryKey: "ADJUST_KEY") as? String;
        if (adjustKey != nil) {
            let adjustConfig = ADJConfig(
                appToken: adjustKey!,
                environment: ADJEnvironmentProduction)

            Adjust.appDidLaunch(adjustConfig)
            
            if ConfigurationManager.manager.configuration == .full {
                Adjust.disableThirdPartySharing();
            }
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open inputURL: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard let documentBrowserViewController = window?.rootViewController as? DocumentBrowserViewController else {
            fatalError("documentBrowserViewController is null")
            
            return false
        }
        
        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let inboxUrl = documentsUrl.appendingPathComponent("Inbox")

        let destinationUrl: URL
        if (inputURL.absoluteString.contains(inboxUrl.absoluteString)) {
            do {
                destinationUrl = documentsUrl.appendingPathComponent(inputURL.lastPathComponent)

                try FileManager.default.moveItem(at: inputURL, to: destinationUrl)
            } catch {
                Crashlytics.crashlytics().record(error: error)
                fatalError("copying from Inbox failed")
                
                return false
            }
        } else {
            destinationUrl = inputURL
        }
        
        documentBrowserViewController.revealDocument(at: destinationUrl, importIfNeeded: true) { (revealedDocumentURL, error) in
            guard let documentUrl = revealedDocumentURL else {
                // ignoring errors because they should pop up in failedToImportDocumentAt too
                
                return;
            }
            
            documentBrowserViewController.presentDocument(at: documentUrl)
        }

        return true
    }
    
}

