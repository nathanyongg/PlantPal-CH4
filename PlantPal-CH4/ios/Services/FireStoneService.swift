//
//  FireStoneService.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 08/07/26.
//
import Foundation
import FirebaseFirestore

@MainActor
final class FirestoreService {

    static let shared = FirestoreService()

    private enum Collection {
        static let plants = "plants"
        static let healthLogs = "health_logs"
        static let deviceTokens = "device_tokens"
    }

    private lazy var db = Firestore.firestore()

    private init() { }

    @discardableResult
    func ensureCloudID(for plant: PlantProfile) -> String {
        if let cloudID = plant.cloudID, !cloudID.isEmpty {
            return cloudID
        }

        let cloudID = UUID().uuidString
        plant.cloudID = cloudID
        return cloudID
    }

    func uploadPlant(_ plant: PlantProfile) async throws {
        let cloudID = ensureCloudID(for: plant)
        let firestorePlant = FirestorePlant(from: plant)

        try await setData(
            firestorePlant.firestoreData,
            at: db.collection(Collection.plants).document(cloudID),
            merge: true
        )
    }

    func deletePlant(_ plant: PlantProfile) async throws {
        guard let cloudID = plant.cloudID, !cloudID.isEmpty else { return }

        try await deleteDocument(db.collection(Collection.plants).document(cloudID))
    }

    func uploadHealthLog(_ entry: PlantHealthLogEntry, for plant: PlantProfile) async throws {
        let cloudID = ensureCloudID(for: plant)

        let data: [String: Any] = [
            "plantID": cloudID,
            "timestamp": Timestamp(date: entry.timestamp),
            "temperature": entry.temperature,
            "humidity": entry.humidity,
            "soilMoisture": entry.soilMoisture,
            "lightIntensity": entry.lightIntensity,
            "status": entry.status
        ]

        try await addDocument(
            data,
            to: db
                .collection(Collection.plants)
                .document(cloudID)
                .collection(Collection.healthLogs)
        )

        try await addDocument(data, to: db.collection(Collection.healthLogs))
    }

    func uploadDeviceToken(_ token: String) async throws {
        let data: [String: Any] = [
            "token": token,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await setData(
            data,
            at: db.collection(Collection.deviceTokens).document(token),
            merge: true
        )
    }

    func fetchPlants() async throws -> [FirestorePlant] {
        let snapshot = try await getDocuments(from: db.collection(Collection.plants))
        return snapshot.documents.compactMap { document in
            FirestorePlant(id: document.documentID, data: document.data())
        }
    }

    private func setData(
        _ data: [String: Any],
        at document: DocumentReference,
        merge: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func addDocument(
        _ data: [String: Any],
        to collection: CollectionReference
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            collection.addDocument(data: data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteDocument(_ document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func getDocuments(from collection: CollectionReference) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            collection.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirestoreServiceError.emptySnapshot)
                }
            }
        }
    }
}

enum FirestoreServiceError: LocalizedError {
    case emptySnapshot

    var errorDescription: String? {
        switch self {
        case .emptySnapshot:
            return "Firestore returned no plant data."
        }
    }
}

private extension FirestorePlant {

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "nickname": nickname,
            "addedAt": Timestamp(date: addedAt),
            "minTemperatureC": minTemperatureC,
            "maxTemperatureC": maxTemperatureC,
            "minHumidityPercent": minHumidityPercent,
            "maxHumidityPercent": maxHumidityPercent,
            "minSoilMoisturePercent": minSoilMoisturePercent,
            "maxSoilMoisturePercent": maxSoilMoisturePercent,
            "minLightLux": minLightLux,
            "maxLightLux": maxLightLux,
            "lastStatus": lastStatus,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        data["linkedDeviceID"] = linkedDeviceID
        data["linkedDeviceName"] = linkedDeviceName
        data["sensorBaseURL"] = sensorBaseURL
        data["lastReadingAt"] = lastReadingAt.map(Timestamp.init(date:))
        data["lastTemperatureC"] = lastTemperatureC
        data["lastHumidityPercent"] = lastHumidityPercent
        data["lastSoilMoisturePercent"] = lastSoilMoisturePercent
        data["lastLightLux"] = lastLightLux

        return data.compactMapValues { value in
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle == .optional else { return value }
            return mirror.children.first?.value
        }
    }
}

private extension FirestorePlant {

    init?(id: String, data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let nickname = data["nickname"] as? String,
            let minTemperatureC = data["minTemperatureC"] as? Double,
            let maxTemperatureC = data["maxTemperatureC"] as? Double,
            let minHumidityPercent = data["minHumidityPercent"] as? Double,
            let maxHumidityPercent = data["maxHumidityPercent"] as? Double,
            let minSoilMoisturePercent = data["minSoilMoisturePercent"] as? Double,
            let maxSoilMoisturePercent = data["maxSoilMoisturePercent"] as? Double,
            let minLightLux = data["minLightLux"] as? Double,
            let maxLightLux = data["maxLightLux"] as? Double,
            let lastStatus = data["lastStatus"] as? String
        else { return nil }
        self.name = name
        self.nickname = nickname
        self.addedAt = (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.linkedDeviceID = data["linkedDeviceID"] as? String
        self.linkedDeviceName = data["linkedDeviceName"] as? String
        self.sensorBaseURL = data["sensorBaseURL"] as? String
        self.minTemperatureC = minTemperatureC
        self.maxTemperatureC = maxTemperatureC
        self.minHumidityPercent = minHumidityPercent
        self.maxHumidityPercent = maxHumidityPercent
        self.minSoilMoisturePercent = minSoilMoisturePercent
        self.maxSoilMoisturePercent = maxSoilMoisturePercent
        self.minLightLux = minLightLux
        self.maxLightLux = maxLightLux
        self.lastReadingAt = (data["lastReadingAt"] as? Timestamp)?.dateValue()
        self.lastStatus = lastStatus
        self.lastTemperatureC = data["lastTemperatureC"] as? Double
        self.lastHumidityPercent = data["lastHumidityPercent"] as? Double
        self.lastSoilMoisturePercent = data["lastSoilMoisturePercent"] as? Double
        self.lastLightLux = data["lastLightLux"] as? Double
        self.id = id
    }
}
