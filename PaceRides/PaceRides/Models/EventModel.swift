//
//  EventReference.swift
//  PaceRides
//
//  Created by Grant Broadwater on 10/16/18.
//  Copyright © 2018 PaceRides. All rights reserved.
//

import Foundation
import Firebase


enum EventDBKeys: String {
    case events = "events"
    case title = "title"
    case organization = "organization"
    case reference = "reference"
    case rideQueue = "rideQueue"
    case activeRides = "activeRides"
    case riderDisplayName = "riderDisplayName"
    case riderReference = "riderReference"
    case driverDisplayName = "driverDisplayName"
    case driverRidference = "driverReference"
    case timeOfRequest = "timeOfRequest"
    case drivers = "drivers"
    case displayName = "displayName"
}


class EventModel {
    
    static let NewData = Notification.Name("NewEventData")
    static let notificationCenter = NotificationCenter.default
    static let db = Firestore.firestore()
    static let ref = EventModel.db.collection(EventDBKeys.events.rawValue)
    
    private var data: [String: Any]? = nil
    
    let uid: String
    
    var reference: DocumentReference
    
    private var _title: String?
    var title: String? {
        get {
            if let _title = self._title {
                return _title
            }
            if let data = self.data {
                return data[OrgDBKeys.title.rawValue] as? String
            }
            return nil
        }
    }
    

    private var _organization: OrganizationModel?
    var organization: OrganizationModel? {
        get {
            return self._organization
        }
    }
    
    private var _rideQueue = [RideModel]()
    var rideQueue: [RideModel] {
        get {
            return self._rideQueue
        }
    }
    
    var link: String {
        get {
            return "https://pacerides.com/event?id=\(self.uid)"
        }
    }
    
    
    private var docListener: ListenerRegistration? = nil
    
    
    init(fromReference refDoc: DocumentSnapshot, underOrganization organization: OrganizationModel? = nil) {
        
        self.uid = refDoc.documentID
        self._title = refDoc.data()?[EventDBKeys.title.rawValue] as? String
        self.reference = EventModel.ref.document(self.uid)
        self._organization = organization
    }
    
    
    init(withUID uid: String, andTitle title: String? = nil) {
        
        self.uid = uid
        self._title = title
        self.reference = EventModel.ref.document(self.uid)
        self._organization = nil
    }
    
    
    func addDriver(paceUser: PacePublicProfile, completion: ((Error?) -> Void)? = nil) {
        
        let batch = EventModel.db.batch()
        
        let eventDriverData: [String: Any] = [
            EventDBKeys.displayName.rawValue: paceUser.displayName as Any,
            EventDBKeys.reference.rawValue: paceUser.dbReference
        ]
        let eventDriverRef = self.reference.collection(EventDBKeys.drivers.rawValue).document(paceUser.uid)
        batch.setData(eventDriverData, forDocument: eventDriverRef)
        
        let userDriveForData: [String: Any] = [
            UserDBKeys.driveFor.rawValue: self.reference
        ]
        batch.setData(userDriveForData, forDocument: paceUser.dbReference, merge: true)
        
        batch.commit() { error in
            if let completion = completion {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    
    func stopDriving(paceUser: PaceUser, completion: ((Error?) -> Void)? = nil) {
        
        let batch = EventModel.db.batch()
        
        let eventDriverRef = self.reference.collection(EventDBKeys.drivers.rawValue).document(paceUser.uid)
        batch.deleteDocument(eventDriverRef)
        
        let userDriveForData: [String: Any] = [
            UserDBKeys.driveFor.rawValue: FieldValue.delete()
        ]
        batch.setData(userDriveForData, forDocument: paceUser.dbReference, merge: true)
        
        batch.commit() { error in
            if let completion = completion {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    
    /// Adds using block to notification obersvers then fetches
    func subscribe(using block: @escaping (Notification) -> Void) {
        EventModel.notificationCenter.addObserver(
            forName: EventModel.NewData,
            object: self,
            queue: OperationQueue.main,
            using: block
        )
        fetch()
    }
    
    
    /// Begins process of pulling down all data relevant to this organization
    func fetch() {
        
        guard self.docListener == nil else {
            EventModel.notificationCenter.post(
                name: EventModel.NewData,
                object: self
            )
            return
        }
        
        docListener = self.reference.addSnapshotListener(self.snapshotListener)
        self.reference.collection(EventDBKeys.rideQueue.rawValue)
            .order(by: EventDBKeys.timeOfRequest.rawValue, descending: false)
            .addSnapshotListener(self.rideQueueListener)
    }
    
    
    func getNextRiderInQueue(_ paceUser: PacePublicProfile) {
        
        guard self.rideQueue.count > 0 else {
            return
        }
        
        self.dequeRideFormRideQueue(paceUser, rideQueueIdx: 0)
    }
    
    
    private func dequeRideFormRideQueue(_ paceUser: PacePublicProfile, rideQueueIdx: Int) {
        
        guard self.rideQueue.count > rideQueueIdx else {
            // TODO
            return
        }
        
        let ride = self.rideQueue[rideQueueIdx];
        let rideQueueRideRef = self.reference.collection(EventDBKeys.rideQueue.rawValue).document(ride.uid)
        let activeRidesRideRef = self.reference.collection(EventDBKeys.activeRides.rawValue).document(ride.uid)
        var updatedRideData: [String: Any] = [
            RideDBKeys.status.rawValue: 1
        ]
        let userDriveData: [String: Any] = [
            UserDBKeys.drive.rawValue: ride.reference
        ]
        
        EventModel.db.runTransaction({ transaction, errorPointer -> Any? in
            
            let rideQueueRideDoc: DocumentSnapshot
            do {
                try rideQueueRideDoc = transaction.getDocument(rideQueueRideRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard let data = rideQueueRideDoc.data() else {
                let error = NSError(
                    domain: "PaceRidesDequeRideErrorDomain",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not retrieve data from rideQueueRide \(ride.uid)"]
                )
                errorPointer?.pointee = error
                return nil
            }
            
            guard let _ = data[EventDBKeys.reference.rawValue] as? DocumentReference else {
                let error = NSError(
                    domain: "PaceRidesDequeRideErrorDomain",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No data in rideQueueRide \(ride.uid)"]
                )
                errorPointer?.pointee = error
                return nil
            }
            
            var activeRideData = data
            activeRideData[EventDBKeys.driverDisplayName.rawValue] = paceUser.displayName as Any
            activeRideData[EventDBKeys.driverRidference.rawValue] = paceUser.dbReference
            
            updatedRideData[RideDBKeys.driver.rawValue] = [
                RideDBKeys.displayName.rawValue: paceUser.displayName as Any,
                RideDBKeys.reference.rawValue: paceUser.dbReference
            ] as [String: Any]
            
            transaction.deleteDocument(rideQueueRideRef)
            transaction.setData(activeRideData, forDocument: activeRidesRideRef)
            transaction.setData(updatedRideData, forDocument: ride.reference, merge: true)
            transaction.setData(userDriveData, forDocument: paceUser.dbReference, merge: true)
            return ride.reference
        }) { object, error in
            
            guard error == nil else {
                let error = error! as NSError
                
                if error.code == -1 || error.code == -2 {
                    print(error.localizedDescription)
                } else {
                    print(error.localizedDescription)
                }
                
                return
            }
            
            guard let dequeuedRideRef = object as? DocumentReference else {
                print("Transaction result not document reference")
                return
            }
            
            print("Successfully dequeued ride \(dequeuedRideRef.documentID)")
        }
    }
    
    func endDrive(_ driver: PacePublicProfile, rideModel: RideModel) {
        
        let batch = EventModel.db.batch()
        
        let activeRidesRideRef = self.reference.collection(EventDBKeys.activeRides.rawValue).document(rideModel.uid)
        batch.deleteDocument(activeRidesRideRef)
        
        batch.deleteDocument(rideModel.reference)
        
        let newDriverData: [String: Any] = [
            UserDBKeys.drive.rawValue: FieldValue.delete()
        ]
        batch.setData(newDriverData, forDocument: driver.dbReference, merge: true)
        
        batch.commit()
    }
    
    private func snapshotListener(document: DocumentSnapshot?, error: Error?) {
        
        guard error == nil else {
            print(error!.localizedDescription)
            return
        }
        
        guard let document = document else {
            print("No event document for uid: \(self.uid)")
            return
        }
        
        guard let docData = document.data() else {
            print("No data in document for event uid: \(self.uid)")
            return
        }
        
        self.data = docData
        
        if let newTitle = docData[OrgDBKeys.title.rawValue] as? String {
            self._title = newTitle
        }
        
        if let newOrgData = docData[EventDBKeys.organization.rawValue] as? [String: Any],
            let newOrgRef = newOrgData[EventDBKeys.reference.rawValue] as? DocumentReference {
            
            if self._organization == nil || self._organization!.uid != newOrgRef.documentID {
                self._organization = OrganizationModel(
                    withTitle: newOrgData[EventDBKeys.title.rawValue] as? String,
                    andReference: newOrgRef
                )
            }
        }
        
        EventModel.notificationCenter.post(
            name: EventModel.NewData,
            object: self
        )
    }
    
    
    private func rideQueueListener(snapshot: QuerySnapshot?, error: Error?) {
        
        guard error == nil else {
            print(error!.localizedDescription)
            return
        }
        
        guard let snapshot = snapshot else {
            print("No ride queue snapshot for event: \(self.uid)")
            return
        }
        
        self._rideQueue.removeAll()
        for document in snapshot.documents {
            let rideRef = RideModel(fromUID: document.documentID) 
            self._rideQueue.append(rideRef)
        }
        
        EventModel.notificationCenter.post(
            name: EventModel.NewData,
            object: self
        )
    }
}
