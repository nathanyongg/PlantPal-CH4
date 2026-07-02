import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — SensorReading
//
// All values are in human-readable units — °C, %, lux.
// Raw ADC conversion happens in the wire decoder below so
// everything downstream (detector, FM prompt, UI) works in
// the same units that Gemini's thresholds use.
// ══════════════════════════════════════════════════════════════

struct SensorReading: Codable, Equatable, Sendable {
    let timestamp:     Date
    let temperature:   Double   // °C      — from DHT11
    let humidity:      Double   // %       — from DHT11
    let soilMoisture:  Double   // %       — from soil probe (0–100)
    let lightIntensity: Double  // lux     — converted from raw ADC

    var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Wire decoding
//
// ESP32 sends compact JSON:
// {"t":24.6,"h":61.2,"m":45.0,"l":2048}
//
//   t → temperature in °C (DHT11 already outputs °C)
//   h → humidity in %     (DHT11 already outputs %)
//   m → soil moisture in % (firmware maps ADC → 0–100 before sending)
//   l → raw photoresistor ADC value (0–4095 on ESP32 12-bit ADC)
//
// Only light needs conversion here. Temperature, humidity, and
// soil moisture arrive in final units from the firmware.
// ══════════════════════════════════════════════════════════════

extension SensorReading {

    private struct WirePayload: Decodable {
        let t: Double   // temperature °C
        let h: Double   // humidity %
        let m: Double   // soil moisture %
        let l: Double   // raw ADC (0–4095)
    }

    init(wireData: Data, receivedAt: Date = Date()) throws {
        let payload = try JSONDecoder().decode(WirePayload.self, from: wireData)
        self.timestamp      = receivedAt
        self.temperature    = payload.t
        self.humidity       = payload.h
        self.soilMoisture   = payload.m
        self.lightIntensity = SensorReading.rawAdcToLux(payload.l)
    }

    // ── Raw ADC → lux conversion for KY-018 ─────────────────
    //
    // KY-018 wiring (pull-down):
    //   Bright light → low resistance → voltage drops → ADC near 0
    //   Dark          → high resistance → voltage rises → ADC near 4095
    //
    // So the mapping is INVERTED:
    //   ADC 0    ≈ 100,000 lux  (flashlight directly on sensor)
    //   ADC 4095 ≈ 0 lux        (fully covered)
    //
    // We invert first, then scale linearly to lux.
    private static func rawAdcToLux(_ rawADC: Double) -> Double {
        let maxADC: Double = 4095
        let maxLux: Double = 100_000
        let inverted = maxADC - rawADC          // flip: 0 → 4095, 4095 → 0
        let lux = (inverted / maxADC) * maxLux
        return lux.rounded()
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: — Validity check
//
// Validates converted values (lux, not raw ADC).
// Common ESP32 failure modes:
//   DHT11 disconnect  → NaN
//   Soil probe short  → negative or >100
//   Photoresistor     → saturated at 0 or 4095 (≈ 0 or 100k lux)
// ══════════════════════════════════════════════════════════════

extension SensorReading {

    var isValid: Bool {
        guard temperature.isFinite, humidity.isFinite,
              soilMoisture.isFinite, lightIntensity.isFinite else { return false }
        guard (-10...60).contains(temperature)       else { return false }
        guard (0...100).contains(humidity)           else { return false }
        guard (0...100).contains(soilMoisture)       else { return false }
        guard (0...100_000).contains(lightIntensity) else { return false }
        return true
    }
}
