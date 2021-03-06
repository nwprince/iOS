//
//  RideModel.swift
//  PaceRides
//
//  Created by Grant Broadwater on 10/17/18.
//  Copyright © 2018 PaceRides. All rights reserved.
//

import Foundation
import Firebase
import CoreLocation

enum RideDBKeys: String {
    case rides = "rides"
    case rider = "rider"
    case driver = "driver"
    case event = "event"
    case status = "status"
    
    case pickupLocation = "pickupLocation"
    case displayName = "displayName"
    case title = "title"
    case reference = "reference"
    case timeOfRequest = "timeOfRequest"
}

enum RideStatus: Int {
    case queued = 0
    case accepted = 1
    case connected = 2
    case completed = 3
}

class RideModel {
    
    static let db = Firestore.firestore()
    static let ref = RideModel.db.collection(RideDBKeys.rides.rawValue)
    static let notificationCenter = NotificationCenter.default
    static let NewData = Notification.Name("NewRideData")
    static let RideDoesNotExist = Notification.Name("RideDoesNotExits")
    
    static func createNewRide(rider: PacePublicProfile, event: EventModel, location loc: CLLocationCoordinate2D, completion: ((Error?) -> Void)? = nil) {
    
        let batch = RideModel.db.batch()
        let rideTime = Timestamp()
        
        // Set ride space
        let rideEventData: [String: Any] = [
            RideDBKeys.title.rawValue: event.title as Any,
            RideDBKeys.reference.rawValue: event.reference
        ]
        let rideRiderData: [String: Any] = [
            RideDBKeys.displayName.rawValue: rider.displayName as Any,
            RideDBKeys.reference.rawValue: rider.dbReference
        ]
        let pickupLocation = GeoPoint(latitude: loc.latitude, longitude: loc.longitude)
        let rideData: [String: Any] = [
            RideDBKeys.rider.rawValue: rideRiderData,
            RideDBKeys.event.rawValue: rideEventData,
            RideDBKeys.pickupLocation.rawValue: pickupLocation,
            RideDBKeys.status.rawValue: RideStatus.queued.rawValue,
            RideDBKeys.timeOfRequest.rawValue: rideTime
        ]
        let rideRef = RideModel.ref.document()
        batch.setData(rideData, forDocument: rideRef)
        
        // Set rider space
        let riderData: [String: Any] = [
            UserDBKeys.ride.rawValue: rideRef
        ]
        batch.setData(riderData, forDocument: rider.dbReference, merge: true)
        
        // Set event space
        let eventRideQueueData: [String: Any] = [
            EventDBKeys.reference.rawValue: rideRef,
            EventDBKeys.riderDisplayName.rawValue: rider.displayName as Any,
            EventDBKeys.riderReference.rawValue: rider.dbReference,
            EventDBKeys.timeOfRequest.rawValue: rideTime
        ]
        let eventRideQueueRef = event.reference.collection(EventDBKeys.rideQueue.rawValue).document(rideRef.documentID)
        batch.setData(eventRideQueueData, forDocument: eventRideQueueRef)
        
        // Comit writes
        batch.commit(completion: completion)
    }
    
    
    let uid: String
    let reference: DocumentReference
    
    private var _eventTitle: String?
    var eventTitle: String? {
        return self._eventTitle
    }
    
    var eventUID: String? {
        return self._eventReference?.documentID
    }
    
    private var _eventReference: DocumentReference?
    var eventReference: DocumentReference? {
        return self._eventReference
    }
    
    private var _riderDisplayName: String?
    var riderDisplayName: String? {
        return self._riderDisplayName
    }
    
    var riderUID: String? {
        return self._riderReference?.documentID
    }
    
    private var _riderReference: DocumentReference?
    var riderReference: DocumentReference? {
        return self._riderReference
    }
    
    private var _status: Int?
    var status: Int? {
        get {
            return self._status
        }
    }
    
    private var _pickupLocation: CLLocation?
    var pickupLocation: CLLocation? {
        get {
            return self._pickupLocation
        }
    }
    
    
    private var docListener: ListenerRegistration?
    
    
    init(fromReference ref: DocumentReference) {
        self.uid = ref.documentID
        self.reference = ref
    }
    
    
    init(fromUID uid: String) {
        self.uid = uid
        self.reference = RideModel.ref.document(self.uid)
    }
    
    
    /// Adds using block to notification obersvers then fetches
    func subscribe(using block: @escaping (Notification) -> Void) {
        RideModel.notificationCenter.addObserver(
            forName: RideModel.NewData,
            object: self,
            queue: OperationQueue.main,
            using: block
        )
        
        fetch()
    }
    
    
    /// Begins process of pulling down all data relevant to this organization
    func fetch() {
        
        guard self.docListener == nil else {
            RideModel.notificationCenter.post(
                name: RideModel.NewData,
                object: self
            )
            return
        }
        
        docListener = self.reference.addSnapshotListener(self.snapshotListener)
    }
    
    
    func cancelRequest(
        forRider rider: PaceUser,
        toEvent eventUID: String? = nil,
        completion: ((Error?) -> Void)? = nil
    ) {
        
        let batch = RideModel.db.batch()
        
        // Set ride space
        batch.deleteDocument(self.reference)
        
        // Set rider space
        let riderData: [String: Any] = [
            UserDBKeys.ride.rawValue: FieldValue.delete()
        ]
        batch.setData(riderData, forDocument: rider.dbReference, merge: true)
        
        
        var eid = eventUID
        if eid == nil, let eUID  = self.eventUID {
            eid = eUID
        }
        
        // Set event space
        if let eventUID = eid {
            let eventRideQueueRef = EventModel.ref
                                        .document(eventUID)
                                        .collection(EventDBKeys.rideQueue.rawValue)
                                        .document(self.uid)
            batch.deleteDocument(eventRideQueueRef)
            let eventActiveRidesRef = EventModel.ref
                                        .document(eventUID)
                                        .collection(EventDBKeys.activeRides.rawValue)
                                        .document(self.uid)
            batch.deleteDocument(eventActiveRidesRef)
        }
        
        // Comit writes
        batch.commit(completion: completion)
    }
    
    
    private func snapshotListener(document: DocumentSnapshot?, error: Error?) {
        
        guard error == nil else {
            print(error!.localizedDescription)
            return
        }
        
        guard let document = document else {
            print("No ride document for uid: \(self.uid)")
            return
        }
        
        guard let docData = document.data() else {
            RideModel.notificationCenter.post(
                name: RideModel.RideDoesNotExist,
                object: self
            )
            
            self._riderDisplayName = nil
            self._riderReference = nil
            self._eventTitle = nil
            self._eventReference = nil
            self._status = nil
            self._pickupLocation = nil
            
            return
        }
        
        if let status = docData[RideDBKeys.status.rawValue] as? Int {
            self._status = status
        } else {
            self._status = nil
        }
        
        if let eventData = docData[RideDBKeys.event.rawValue] as? [String: Any] {
            self._eventTitle = eventData[RideDBKeys.title.rawValue] as? String
            self._eventReference = eventData[RideDBKeys.reference.rawValue] as? DocumentReference
        } else {
            self._eventTitle = nil
            self._eventReference = nil
        }
        
        
        if let riderData = docData[RideDBKeys.rider.rawValue] as? [String: Any] {
            self._riderDisplayName = riderData[RideDBKeys.displayName.rawValue] as? String
            self._riderReference = riderData[RideDBKeys.reference.rawValue] as? DocumentReference
        } else {
            self._riderDisplayName = nil
            self._riderReference = nil
        }
        
        if let pickupLocation = docData[RideDBKeys.pickupLocation.rawValue] as? GeoPoint {
            self._pickupLocation = CLLocation(
                latitude: pickupLocation.latitude,
                longitude: pickupLocation.longitude
            )
        } else {
            self._pickupLocation = nil
        }
        
        RideModel.notificationCenter.post(
            name: RideModel.NewData,
            object: self
        )
    }
}
