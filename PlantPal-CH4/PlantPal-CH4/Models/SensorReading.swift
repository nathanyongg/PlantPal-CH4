import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — SensorReading
//
// Raw values as they arrive from the ESP32. This is the only
// model that touches the wire format — everything downstream
// (Detection, Reasoning) works with this typed struct, never
// raw bytes or JSON.
// ══════════════════════════════════════════════════════════════

struct SensorReading: Codable, Equatable, Sendable {
    let timestamp: Date
    let temperature: Double      // °C
    let humidity: Double         // %
    let soilMoisture: Double     // %
    let lightIntensity: Double   // lux

    var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Wire decoding
//
// What the ESP32 actually sends over NWConnection. Keep this
// separate from SensorReading so a firmware field rename or unit
// change doesn't ripple through the rest of the app — only this
// initializer needs to change.
// ══════════════════════════════════════════════════════════════

extension SensorReading {

    // ESP32 firmware sends compact JSON like:
    // {"t":24.6,"h":61.2,"m":45.0,"l":19872}
    private struct WirePayload: Decodable {
        let t: Double   // temperature
        let h: Double   // humidity
        let m: Double   // soil moisture
        let l: Double   // light intensity
    }

    init(wireData: Data, receivedAt: Date = Date()) throws {
        let payload = try JSONDecoder().decode(WirePayload.self, from: wireData)
        self.timestamp      = receivedAt
        self.temperature    = payload.t
        self.humidity       = payload.h
        self.soilMoisture   = payload.m
        self.lightIntensity = payload.l
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Validity check
//
// ESP32 sensors fail in predictable ways: disconnected DHT11
// reads as NaN, photoresistor saturates at 0 or max, soil probe
// reads negative when dry-shorted. Catch these before they reach
// the detector or get logged as real data.
// ══════════════════════════════════════════════════════════════

extension SensorReading {

    var isValid: Bool {
        guard temperature.isFinite, humidity.isFinite,
              soilMoisture.isFinite, lightIntensity.isFinite else {
            return false
        }
        guard (-10...60).contains(temperature) else { return false }
        guard (0...100).contains(humidity) else { return false }
        guard (0...100).contains(soilMoisture) else { return false }
        guard (0...100_000).contains(lightIntensity) else { return false }
        return true
    }
}
