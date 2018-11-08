//
//  AppDelegate.swift
//  PaceRides
//
//  Created by Grant Broadwater on 9/30/18.
//  Copyright © 2018 PaceRides. All rights reserved.
//

import UIKit
import Firebase
import UserNotifications
import FBSDKCoreKit

enum TransitionDestination {
    case organization(String)
    case event(String)
}

enum UserDefaultsKeys: String {
    case EULAAgreementSeconds = "EULAAgreementSeconds"
}

enum DataDBKeys: String {
    case data = "data"
    case eula = "eula"
    case author = "author"
}

enum EULADBKeys: String {
    case text = "text"
    case timestamp = "timestamp"
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate {

    var window: UIWindow?
    var fcmToken: String?

    var transitionDestination: TransitionDestination? = nil
    
    override init() {
        super.init()
        
        FirebaseApp.configure()
        
        let db = Firestore.firestore()
        let settings = db.settings
        settings.areTimestampsInSnapshotsEnabled = true
        db.settings = settings
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        Auth.auth().addStateDidChangeListener(UserModel.firebaseAuthStateChangeListener)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        self.window = UIWindow(frame: UIScreen.main.bounds)
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let mainLaunchScreen = storyboard.instantiateViewController(withIdentifier: "launchscreen") as! LaunchScreenViewController
        self.window?.rootViewController = mainLaunchScreen
        self.window?.makeKeyAndVisible()
        mainLaunchScreen.activityIndicator.isHidden = false
        mainLaunchScreen.activityIndicator.startAnimating()
        
        self.registerForNotifications()
        
        let eulaAgreementSeconds
            = UserDefaults.standard.object(forKey: UserDefaultsKeys.EULAAgreementSeconds.rawValue) as? NSNumber
        
        if let eulaAgreementSeconds = eulaAgreementSeconds, eulaAgreementSeconds.int64Value > 0 {
            
            Firestore.firestore().collection(DataDBKeys.data.rawValue)
                .document(DataDBKeys.eula.rawValue).getDocument() { document, error in
                    
                    // TODO: Handle errors
                    guard error == nil else {
                        print(error!.localizedDescription)
                        
                        mainLaunchScreen.activityIndicator.stopAnimating()
                        
                        let alert = UIAlertController(
                            title: "Error",
                            message: error!.localizedDescription,
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(
                            UIAlertAction(
                                title: "Okay",
                                style: .default,
                                handler: nil
                            )
                        )
                        
                        mainLaunchScreen.present(alert, animated: true)
                        
                        return
                    }
                    
                    guard let data = document?.data() else {
                        print("No data in eula")
                        return
                    }
                    
                    guard let eulaTimestamp = data[EULADBKeys.timestamp.rawValue] as? Timestamp else {
                        print("No eula text")
                        return
                    }
                    
                    if eulaAgreementSeconds.int64Value > eulaTimestamp.seconds {
                        mainLaunchScreen.performSegue(withIdentifier: "startApplication", sender: nil)
                    } else {
                        self.displayEULAViewController()
                    }
            }
        } else {
            self.displayEULAViewController()
        }
        
        return FBSDKApplicationDelegate.sharedInstance()!.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func displayEULAViewController() {
        
        let eulaRef = Firestore.firestore().collection(DataDBKeys.data.rawValue).document(DataDBKeys.eula.rawValue)
        eulaRef.getDocument() { document, error in
            
            // TODO: Handle errors
            guard error == nil else {
                print(error!.localizedDescription)
                return
            }
            
            guard let data = document?.data() else {
                print("No data in eula")
                return
            }
            
            guard let eulaText = data[EULADBKeys.text.rawValue] as? String else {
                print("No eula text")
                return
            }
            
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let viewcontroller = storyboard.instantiateViewController(withIdentifier: "EULAViewController") as! EULAViewController
            viewcontroller.eulaText = eulaText
            self.window?.rootViewController = viewcontroller
            self.window?.makeKeyAndVisible()
            
        }
        
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        let handled = FBSDKApplicationDelegate.sharedInstance()!.application(
            app,
            open: url,
            sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String,
            annotation: options[UIApplication.OpenURLOptionsKey.annotation]
        )
        return handled
    }
    
    
    private func queryParameters(from url: URL) -> [String: String] {
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryParams = [String: String]()
        for queryItem: URLQueryItem in (urlComponents?.queryItems)! {
            if queryItem.value == nil {
                continue
            }
            queryParams[queryItem.name] = queryItem.value
        }
        return queryParams
    }
    
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        
//        print("Continue user activity")
        
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            if let url = userActivity.webpageURL {
                
                guard let host = url.host, host.lowercased() == "pacerides.com" else {
                    return true
                }
                
                if url.path.lowercased().contains("organization"), let orgId = queryParameters(from: url)["id"] {
                    self.transitionDestination = TransitionDestination.organization(orgId)
                }
                
                if url.path.lowercased().contains("event"), let eventId = queryParameters(from: url)["id"] {
                    self.transitionDestination = TransitionDestination.event(eventId)
                }
                
                let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
                let revealVC = mainStoryboard.instantiateViewController(withIdentifier: "RevealVC")
                self.window?.rootViewController = revealVC
                self.window?.makeKeyAndVisible()
            }
        }
        
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        
        Messaging.messaging().shouldEstablishDirectChannel = false
        Messaging.messaging().useMessagingDelegateForDirectChannel = false
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        
        Messaging.messaging().shouldEstablishDirectChannel = false
        Messaging.messaging().useMessagingDelegateForDirectChannel = false
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        
        Messaging.messaging().shouldEstablishDirectChannel = true
        Messaging.messaging().useMessagingDelegateForDirectChannel = true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        Messaging.messaging().shouldEstablishDirectChannel = true
        Messaging.messaging().useMessagingDelegateForDirectChannel = true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        
        Messaging.messaging().shouldEstablishDirectChannel = false
        Messaging.messaging().useMessagingDelegateForDirectChannel = false
    }
}



extension AppDelegate: UNUserNotificationCenterDelegate {
    
    private func registerForNotifications() {
        
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            
            guard error == nil else {
                
                print("Error")
                print(error!.localizedDescription)
                
                return
            }
            
            guard granted else {
                
                guard let window = self.window, let viewController = window.rootViewController else {
                    print("Needs notification privilidge!")
                    print("The App needs notification privilidges\n\nPlease allow this in your device settings.")
                    return
                }
                
                let alert = UIAlertController(
                    title: "Needs Notification Privilidge",
                    message: "\nThis App needs notification privilidges.\n\nPlease allow this in your device settings.",
                    preferredStyle: .alert
                )
                
                alert.addAction(
                    UIAlertAction(title: "Settings", style: .default) { _ in
                        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        
                        if UIApplication.shared.canOpenURL(settingsUrl) {
                            UIApplication.shared.open(settingsUrl) { success in
                                print("Setting is opened: \(success)")
                            }
                        }
                    }
                )
                
                alert.addAction(
                    UIAlertAction(
                        title: "Okay",
                        style: .cancel,
                        handler: nil
                    )
                )
                
                viewController.present(alert, animated: true)
                return
            }
            
            Messaging.messaging().shouldEstablishDirectChannel = true
            Messaging.messaging().useMessagingDelegateForDirectChannel = true
        }
        
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    
    func sendLocalNotificaiton(withTitle title: String, andBody body: String, after timeInterval: Double = 1) {
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            
            guard error == nil else {
                print("Error")
                print(error!.localizedDescription)
                return
            }
        }
    }
    
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        Messaging.messaging().apnsToken = deviceToken
        
        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        print()
        print("application:didRegisterForRemoteNotificationsWithDeviceToken")
        print("Token: \(hexToken)")
    }
    
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        
        print()
        print("application:didFailToRegisterForRemoteNotificationsWithError")
        print("Error: \(error.localizedDescription)")
    }
    
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        print()
        print("userNotificationCenter:didRecieve:withCompletionHandler")
        print("response UUID: \(response.notification.request.identifier)")
        
        completionHandler()
    }
    
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        
        print()
        print("userNotificationCenter:willPresent:withCompletionHandler")
        print("notification UUID: \(notification.request.identifier)")
        
        completionHandler([.alert, .sound])
    }
    
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        
        Messaging.messaging().appDidReceiveMessage(userInfo)
        
        print()
        print("application:didReceiveRemoteNotification")
        print("User Info: \(userInfo)")
    }
    
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        Messaging.messaging().appDidReceiveMessage(userInfo)
        
        print()
        print("application:didReceiveRemoteNotification:fetchCompletionHandler")
        print("User Info: \(userInfo)")
        
        completionHandler(UIBackgroundFetchResult.newData)
    }
}


extension AppDelegate: MessagingDelegate {
    
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        
        self.fcmToken = fcmToken
        
        print()
        print("Firebase registration token: \(fcmToken)")
        
        let dataDict:[String: String] = ["token": fcmToken]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
    }
    
    
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        
        print()
        print("messaging:didRecieve")
        print("Remote Message: \(remoteMessage)")
        
    }
    
    
    func subscribe(toTopic topic: String, completion: ((Error?) -> Void)? = nil) -> Bool {
        
        guard self.fcmToken != nil else {
            return false
        }
        
        Messaging.messaging().subscribe(toTopic: topic, completion: completion)
        
        return true
    }
    
    
    func unsubscribe(fromTopic topic: String, completion: ((Error?) -> Void)? = nil) -> Bool {
        
        guard self.fcmToken != nil else {
            return false
        }
        
        Messaging.messaging().unsubscribe(fromTopic: topic, completion: completion)
        
        return true
    }
}
