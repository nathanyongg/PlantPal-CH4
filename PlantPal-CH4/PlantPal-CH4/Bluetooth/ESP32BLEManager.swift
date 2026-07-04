import CoreBluetooth
import Foundation
internal import Combine

// ══════════════════════════════════════════════════════════════
// MARK: — ESP32BLEManager
//
// Owns the CoreBluetooth session for pairing with the plant
// sensor and provisioning its Wi-Fi. One shared device for every
// plant, so this isn't per-plant state — it's a single always-on
// connection you set up once (and revisit only if you change
// Wi-Fi networks or swap the sensor).
//
// Flow: scan → connect → discover the GATT service → write Wi-Fi
// credentials → watch the status characteristic until the ESP32
// reports connected/failed.
// ══════════════════════════════════════════════════════════════

@MainActor
final class ESP32BLEManager: NSObject, ObservableObject {

    static let shared = ESP32BLEManager()

    enum ConnectionPhase: Equatable {
        case disconnected
        case scanning
        case connecting
        case discoveringServices
        case readyToProvision
        case sendingCredentials
        case awaitingResult
        case provisioned
        case failed(String)
    }

    struct DiscoveredDevice: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var phase: ConnectionPhase = .disconnected
    @Published private(set) var connectedDeviceName: String?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var credentialsCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?

    private static let pairedDeviceKey = "pairedESP32DeviceIdentifier"

    private var pairedDeviceIdentifier: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.pairedDeviceKey).flatMap(UUID.init)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.pairedDeviceKey)
        }
    }

    var hasPairedDevice: Bool { pairedDeviceIdentifier != nil }

    private override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: — Scanning

    func startScanning() {
        discoveredDevices = []
        guard bluetoothState == .poweredOn else { return }
        phase = .scanning
        central.scanForPeripherals(
            withServices: [BLEProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        central.stopScan()
        if phase == .scanning { phase = .disconnected }
    }

    // MARK: — Connecting

    func connect(to device: DiscoveredDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScanning()
        phase = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    /// Reconnects to whichever device was paired last time, if any —
    /// used on launch so re-provisioning doesn't require re-scanning.
    func reconnectToPairedDevice() {
        guard bluetoothState == .poweredOn, let id = pairedDeviceIdentifier else { return }
        let known = central.retrievePeripherals(withIdentifiers: [id])
        guard let peripheral = known.first else { return }
        phase = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
    }

    func forgetPairedDevice() {
        disconnect()
        pairedDeviceIdentifier = nil
    }

    // MARK: — Provisioning

    func sendWiFiCredentials(ssid: String, password: String) {
        guard
            let peripheral = connectedPeripheral,
            let characteristic = credentialsCharacteristic
        else {
            phase = .failed("Not connected to a device yet.")
            return
        }

        do {
            let payload = try BLEProtocol.WiFiCredentials(ssid: ssid, password: password).encoded()
            phase = .sendingCredentials
            peripheral.writeValue(payload, for: characteristic, type: .withResponse)
        } catch {
            phase = .failed("Couldn't prepare Wi-Fi credentials: \(error.localizedDescription)")
        }
    }

    // MARK: — Private

    private func resetConnectionState() {
        connectedPeripheral = nil
        credentialsCharacteristic = nil
        statusCharacteristic = nil
        connectedDeviceName = nil
        phase = .disconnected
    }
}

// MARK: — CBCentralManagerDelegate

extension ESP32BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn {
            reconnectToPairedDevice()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Plant Sensor"

        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDeviceName = peripheral.name ?? "Plant Sensor"
        phase = .discoveringServices
        peripheral.discoverServices([BLEProtocol.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        phase = .failed(error?.localizedDescription ?? "Couldn't connect to the sensor.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnectionState()
    }
}

// MARK: — CBPeripheralDelegate

extension ESP32BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            phase = .failed(error?.localizedDescription ?? "The sensor didn't expose its Wi-Fi setup service.")
            return
        }
        for service in services where service.uuid == BLEProtocol.serviceUUID {
            peripheral.discoverCharacteristics(
                [BLEProtocol.wifiCredentialsCharacteristicUUID, BLEProtocol.provisioningStatusCharacteristicUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else {
            phase = .failed(error?.localizedDescription ?? "The sensor's Wi-Fi setup service looked incomplete.")
            return
        }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEProtocol.wifiCredentialsCharacteristicUUID:
                credentialsCharacteristic = characteristic

            case BLEProtocol.provisioningStatusCharacteristicUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)

            default:
                break
            }
        }

        if credentialsCharacteristic != nil {
            phase = .readyToProvision
            pairedDeviceIdentifier = peripheral.identifier
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == BLEProtocol.wifiCredentialsCharacteristicUUID else { return }
        if let error {
            phase = .failed("Couldn't send Wi-Fi credentials: \(error.localizedDescription)")
        } else {
            phase = .awaitingResult
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard
            characteristic.uuid == BLEProtocol.provisioningStatusCharacteristicUUID,
            error == nil,
            let data = characteristic.value,
            let status = BLEProtocol.ProvisioningStatus(data: data)
        else { return }

        switch status {
        case .idle:
            break
        case .connecting:
            phase = .awaitingResult
        case .connected:
            phase = .provisioned
        case .failed:
            phase = .failed("The sensor couldn't join that Wi-Fi network. Check the password and try again.")
        }
    }
}
