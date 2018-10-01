//
//  UserModel.swift
//  PaceRides
//
//  Created by Grant Broadwater on 9/30/18.
//  Copyright © 2018 PaceRides. All rights reserved.
//

import Foundation
import Firebase
import FBSDKCoreKit
import FBSDKLoginKit

extension NSNotification.Name {
    public static let UserPublicProfileDidChange = Notification.Name("UserPublicProfileDidChange")
}

class UserProfile {
    
    let uid: String
    var providerId: String? = nil
    var displayName: String? = nil
    var photoUrl: URL? = nil
    
    init(uid: String) {
        self.uid = uid
    }
}

class UserModel: NSObject {
    
    static let sharedInstance = UserModel()
    
    let db = Firestore.firestore()
    let notificationCenter = NotificationCenter.default

    private var _publicProfile: UserProfile? = nil
    var publicProfile: UserProfile? {
        get {
            if let currentAccessToken = FBSDKAccessToken.current() {
                self.userLoggedInWithAccessToken(token: currentAccessToken.tokenString)
            }
            return _publicProfile
        }
        set {
            self._publicProfile = newValue
            self.notificationCenter.post(name: .UserPublicProfileDidChange, object: self)
        }
    }
    
    private override init() {
        super.init()
    }
}

extension UserModel: FBSDKLoginButtonDelegate {
    
    func loginButton(_ loginButton: FBSDKLoginButton!, didCompleteWith result: FBSDKLoginManagerLoginResult!, error: Error!) {
        
        guard error == nil else {
            print(error.localizedDescription)
            return
        }
        
        userLoggedInWithAccessToken(token: result.token.tokenString)
    }
    
    
    func userLoggedInWithAccessToken(token: String) {
        let fbCredential = FacebookAuthProvider.credential(withAccessToken: token)
        Auth.auth().signIn(with: fbCredential) { (authResult, error) in
            
            guard error == nil else {
                print(error!.localizedDescription)
                return
            }
            
            guard let authResult = authResult else {
                print("Auth result invalid")
                return
            }
            
            let newPublicProfile = UserProfile(uid: authResult.uid)
            newPublicProfile.providerId = authResult.providerID
            newPublicProfile.displayName = authResult.displayName
            newPublicProfile.photoUrl = authResult.photoURL
            
            self.publicProfile = newPublicProfile
        }
    }
    
    func loginButtonDidLogOut(_ loginButton: FBSDKLoginButton!) {
        self.publicProfile = nil
    }
    
}