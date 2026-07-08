import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — SensorReading
//
// All values are in human-readable units — °C and %.
// The ESP32 maps raw soil and light ADC readings to 0-100 before
// sending them, so everything downstream works in display units.
// ══════════════════════════════════════════════════════════════

struct SensorReading: Codable, Equatable, Sendable {
    let timestamp:     Date
    let temperature:   Double   // °C      — from DHT11
    let humidity:      Double   // %       — from DHT11
    let soilMoisture:  Double   // %       — from soil probe (0–100)
    let lightIntensity: Double  // %       — from light sensor calibration (0-100)

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
// {"firmware_version":2,"t":24.6,"h":61.2,"m":45,"l":68,"rtc_timestamp":"2026-07-06T07:12:00Z"}
//
//   t → temperature in °C (DHT11 already outputs °C)
//   h → humidity in %     (DHT11 already outputs %)
//   m → soil moisture in % (firmware maps ADC → 0–100 before sending)
//   l → light level in % (firmware maps ADC → 0–100 before sending)
//   rtc_timestamp / timestamp / measured_at / created_at → reading time
//
// All values arrive in final units from the firmware.
// ══════════════════════════════════════════════════════════════

extension SensorReading {

    private struct WirePayload: Decodable {
        let firmwareVersion: Int?
        let timestamp: Date?
        let t: Double   // temperature °C
        let h: Double   // humidity %
        let m: Double   // soil moisture %
        let l: Double   // light %

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case createdAt = "created_at"
            case measuredAt = "measured_at"
            case rtcTimestamp = "rtc_timestamp"
            case firmwareVersion = "firmware_version"
            case t
            case h
            case m
            case l
            case temperature
            case temperatureC = "temperature_c"
            case temp
            case humidity
            case humidityPercent = "humidity_percent"
            case soilMoisture = "soil_moisture"
            case soilMoistureCamel = "soilMoisture"
            case moisture
            case moisturePercent = "moisture_percent"
            case light
            case lightPercent = "light_percent"
            case lightIntensity = "light_intensity"
            case lightRaw = "light_raw"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.firmwareVersion = try Self.decodeOptionalInt(from: container, forKey: .firmwareVersion)
            self.timestamp = try Self.decodeTimestamp(from: container)

            self.t = try Self.decodeRequiredDouble(
                from: container,
                keys: [.t, .temperature, .temperatureC, .temp],
                label: "temperature"
            ).value
            self.h = try Self.decodeRequiredDouble(
                from: container,
                keys: [.h, .humidity, .humidityPercent],
                label: "humidity"
            ).value
            self.m = try Self.decodeRequiredDouble(
                from: container,
                keys: [.m, .soilMoisture, .soilMoistureCamel, .moisture, .moisturePercent],
                label: "soil moisture"
            ).value

            let light = try Self.decodeRequiredDouble(
                from: container,
                keys: [.l, .light, .lightPercent, .lightIntensity, .lightRaw],
                label: "light"
            )
            self.l = Self.normalizedLight(
                light.value,
                decodedFrom: light.key,
                firmwareVersion: firmwareVersion
            )
        }

        private static func decodeTimestamp(
            from container: KeyedDecodingContainer<CodingKeys>
        ) throws -> Date? {
            for key in [CodingKeys.rtcTimestamp, .measuredAt, .timestamp, .createdAt] {
                if let epoch = try? container.decode(Double.self, forKey: key) {
                    return date(fromEpoch: epoch)
                }

                guard let value = try? container.decode(String.self, forKey: key),
                      !value.isEmpty else { continue }

                if let date = ISO8601DateFormatter.plantPalDate(from: value) {
                    return date
                }

                if let epoch = Double(value) {
                    return date(fromEpoch: epoch)
                }
            }

            return nil
        }

        private static func date(fromEpoch value: Double) -> Date {
            let seconds = value > 1_000_000_000_000 ? value / 1_000 : value
            return Date(timeIntervalSince1970: seconds)
        }

        private static func decodeRequiredDouble(
            from container: KeyedDecodingContainer<CodingKeys>,
            keys: [CodingKeys],
            label: String
        ) throws -> (value: Double, key: CodingKeys) {
            for key in keys {
                if let value = try decodeOptionalDouble(from: container, forKey: key) {
                    return (value, key)
                }
            }

            throw DecodingError.keyNotFound(
                keys[0],
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing \(label) in ESP32 sensor payload."
                )
            )
        }

        private static func decodeOptionalDouble(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Double? {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }

            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               let double = Double(value) {
                return double
            }

            return nil
        }

        private static func decodeOptionalInt(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Int? {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }

            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return Int(value)
            }

            return nil
        }

        private static func normalizedLight(
            _ value: Double,
            decodedFrom key: CodingKeys,
            firmwareVersion: Int?
        ) -> Double {
            if key == .lightRaw {
                return clampPercent(value / 4095 * 100)
            }

            let percent = clampPercent(value)

            // Firmware v1 mapped KY-018 light backward for this board, so
            // compact legacy payloads need one compatibility flip.
            if key == .l, firmwareVersion == nil {
                return 100 - percent
            }

            return percent
        }

        private static func clampPercent(_ value: Double) -> Double {
            min(max(value, 0), 100)
        }
    }

    init(wireData: Data, receivedAt: Date = Date()) throws {
        let payload = try JSONDecoder().decode(WirePayload.self, from: wireData)
        self.timestamp      = Self.normalizedTimestamp(payload.timestamp, receivedAt: receivedAt)
        self.temperature    = payload.t
        self.humidity       = payload.h
        self.soilMoisture   = payload.m
        self.lightIntensity = payload.l
    }

    private static func normalizedTimestamp(_ timestamp: Date?, receivedAt: Date) -> Date {
        guard let timestamp else { return receivedAt }

        let oldestAcceptedTimestamp = receivedAt.addingTimeInterval(-365 * 24 * 60 * 60)
        let newestAcceptedTimestamp = receivedAt.addingTimeInterval(5 * 60)
        guard timestamp >= oldestAcceptedTimestamp,
              timestamp <= newestAcceptedTimestamp else {
            return receivedAt
        }

        return timestamp
    }
}

private extension ISO8601DateFormatter {
    static func plantPalDate(from value: String) -> Date? {
        plantPalWithFractionalSeconds.date(from: value) ?? plantPal.date(from: value)
    }

    static let plantPal: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let plantPalWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// ══════════════════════════════════════════════════════════════
// MARK: — Validity check
//
// Validates final display values.
// Common ESP32 failure modes:
//   DHT11 disconnect  → NaN
//   Soil probe short  → negative or >100
//   Photoresistor     → negative or >100 after calibration
// ══════════════════════════════════════════════════════════════

extension SensorReading {

    var isValid: Bool {
        guard temperature.isFinite, humidity.isFinite,
              soilMoisture.isFinite, lightIntensity.isFinite else { return false }
        guard (-10...60).contains(temperature)       else { return false }
        guard (0...100).contains(humidity)           else { return false }
        guard (0...100).contains(soilMoisture)       else { return false }
        guard (0...100).contains(lightIntensity) else { return false }
        guard temperature != 0, humidity != 0 else { return false }
        return true
    }
}
