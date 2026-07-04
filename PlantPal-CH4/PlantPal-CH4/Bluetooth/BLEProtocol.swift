import CoreBluetooth
import Foundation

// ══════════════════════════════════════════════════════════════
// MARK: — BLEProtocol
//
// The GATT contract between this app and the ESP32 firmware.
// One shared sensor, paired once per setup: the phone finds it
// over BLE, hands it Wi-Fi credentials, and the ESP32 takes it
// from there — everything after that (readings, the "worker"
// endpoint PlantDataService talks to) happens over Wi-Fi, not BLE.
//
// These UUIDs must match the firmware's GATT service exactly.
// The ones below are placeholders — swap in the real UUIDs the
// ESP32 side advertises before shipping.
// ══════════════════════════════════════════════════════════════

enum BLEProtocol {

    // MARK: — Identity

    /// Advertised by the ESP32 so scanning can filter to just our
    /// devices instead of listing every nearby BLE accessory.
    static let serviceUUID = CBUUID(string: "7E570001-0000-1000-8000-00805F9B34FB")

    /// Write-only. iOS writes a JSON-encoded `WiFiCredentials` here.
    static let wifiCredentialsCharacteristicUUID = CBUUID(string: "7E570002-0000-1000-8000-00805F9B34FB")

    /// Notify + read. The ESP32 reports provisioning progress here
    /// as a single-byte `ProvisioningStatus.rawValue`.
    static let provisioningStatusCharacteristicUUID = CBUUID(string: "7E570003-0000-1000-8000-00805F9B34FB")

    // MARK: — Payload

    struct WiFiCredentials: Encodable {
        let ssid: String
        let password: String

        /// JSON is easy for the firmware to parse and comfortably
        /// fits a negotiated BLE MTU (iOS typically negotiates
        /// 150–185 bytes) for realistic SSID/password lengths.
        func encoded() throws -> Data {
            try JSONEncoder().encode(self)
        }
    }

    // MARK: — Status

    enum ProvisioningStatus: UInt8 {
        case idle = 0
        case connecting = 1
        case connected = 2
        case failed = 3

        init?(data: Data) {
            guard let byte = data.first else { return nil }
            self.init(rawValue: byte)
        }
    }
}
