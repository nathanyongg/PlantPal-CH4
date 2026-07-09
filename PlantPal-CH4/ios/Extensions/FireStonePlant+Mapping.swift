//
//  FireStonePlant+Mapping.swift
//  CH3-PiecesToProduct-Team1
//
//  Created by Nathan Yong on 08/07/26.
//

import Foundation

extension FirestorePlant {

    init(from plant: PlantProfile) {

        self.name = plant.name
        self.nickname = plant.nickname
        self.addedAt = plant.addedAt

        self.linkedDeviceID = plant.linkedDeviceID
        self.linkedDeviceName = plant.linkedDeviceName
        self.sensorBaseURL = plant.sensorBaseURL

        self.minTemperatureC = plant.minTemperatureC
        self.maxTemperatureC = plant.maxTemperatureC

        self.minHumidityPercent = plant.minHumidityPercent
        self.maxHumidityPercent = plant.maxHumidityPercent

        self.minSoilMoisturePercent = plant.minSoilMoisturePercent
        self.maxSoilMoisturePercent = plant.maxSoilMoisturePercent

        self.minLightLux = plant.minLightLux
        self.maxLightLux = plant.maxLightLux

        self.lastReadingAt = plant.lastReadingAt
        self.lastStatus = plant.lastStatus

        self.lastTemperatureC = plant.lastTemperatureC
        self.lastHumidityPercent = plant.lastHumidityPercent
        self.lastSoilMoisturePercent = plant.lastSoilMoisturePercent
        self.lastLightLux = plant.lastLightLux
        
        self.id = plant.cloudID
    }
    
    func toPlantProfile() -> PlantProfile {

        let thresholds = PlantThresholds(
            minTemperatureC: minTemperatureC,
            maxTemperatureC: maxTemperatureC,
            minHumidityPercent: minHumidityPercent,
            maxHumidityPercent: maxHumidityPercent,
            minSoilMoisturePercent: minSoilMoisturePercent,
            maxSoilMoisturePercent: maxSoilMoisturePercent,
            minLightLux: minLightLux,
            maxLightLux: maxLightLux
        )

        let plant = PlantProfile(
            name: name,
            nickname: nickname,
            thresholds: thresholds,
            linkedDeviceID: linkedDeviceID,
            linkedDeviceName: linkedDeviceName,
            sensorBaseURL: sensorBaseURL
        )

        plant.cloudID = id
        plant.addedAt = addedAt
        plant.lastReadingAt = lastReadingAt
        plant.lastStatus = lastStatus
        plant.lastTemperatureC = lastTemperatureC
        plant.lastHumidityPercent = lastHumidityPercent
        plant.lastSoilMoisturePercent = lastSoilMoisturePercent
        plant.lastLightLux = lastLightLux

        return plant
    }


}
