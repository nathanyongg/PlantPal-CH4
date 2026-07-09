//
//  FireStonePlant.swift
//  PlantPal-CH4
//
//  Created by Nathan Yong on 08/07/26.
//

import FirebaseFirestore

struct FirestorePlant: Codable, Identifiable {

    @DocumentID
    var id: String?

    var name: String
    var nickname: String

    var addedAt: Date

    var linkedDeviceID: String?
    var linkedDeviceName: String?
    var sensorBaseURL: String?

    var minTemperatureC: Double
    var maxTemperatureC: Double

    var minHumidityPercent: Double
    var maxHumidityPercent: Double

    var minSoilMoisturePercent: Double
    var maxSoilMoisturePercent: Double

    var minLightLux: Double
    var maxLightLux: Double

    var lastReadingAt: Date?

    var lastStatus: String

    var lastTemperatureC: Double?
    var lastHumidityPercent: Double?
    var lastSoilMoisturePercent: Double?
    var lastLightLux: Double?

    // We'll ignore images for now
}
