import Foundation
import CoreBluetooth
import Combine

/// Represents a discovered Bluetooth Low Energy OBD-II adapter.
struct DiscoveredOBDDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    static func == (lhs: DiscoveredOBDDevice, rhs: DiscoveredOBDDevice) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rssi == rhs.rssi
    }
}

enum BLEConnectionState: Equatable {
    case bluetoothUnavailable(String)
    case disconnected
    case scanning
    case connecting(String)
    case initializingELM(String)
    case connected(String)
    case error(String)

    var label: String {
        switch self {
        case .bluetoothUnavailable(let msg): return msg
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning for BLE OBD…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .initializingELM(let name): return "Initializing \(name)…"
        case .connected(let name): return "Connected: \(name)"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum OBDCommandError: LocalizedError {
    case notConnected
    case timeout(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "OBD adapter is not connected."
        case .timeout(let cmd): return "Timed out waiting for response to \(cmd)."
        case .writeFailed(let msg): return "Bluetooth write failed: \(msg)"
        }
    }
}

/// CoreBluetooth BLE client supporting all common iOS-compatible ELM327 BLE 4.0+ adapters:
/// Veepeak OBDCheck BLE, Vgate iCar Pro BLE, OBDLink CX, LELink, HM-10 / FFE0, FFF0, and 18F0 dongles.
final class BLEOBDManager: NSObject, ObservableObject {
    @Published private(set) var state: BLEConnectionState = .disconnected
    @Published private(set) var discoveredDevices: [DiscoveredOBDDevice] = []
    @Published private(set) var detectedProtocolName: String = "Auto"
    @Published private(set) var elmVersion: String = "Unknown"
    @Published private(set) var commandLog: [String] = []

    /// Known BLE OBD-II UART service UUIDs
    static let knownServiceUUIDs: [CBUUID] = [
        CBUUID(string: "FFF0"), // Vgate iCar Pro BLE, Veepeak, many ELM327 BLE
        CBUUID(string: "FFE0"), // HM-10 / CC2541 BLE OBD adapters
        CBUUID(string: "18F0"), // Veepeak BLE+ / OBDLink CX style
        CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2") // LELink / IOS-Vlink
    ]

    private static let knownWriteUUIDs: Set<CBUUID> = [
        CBUUID(string: "FFF2"),
        CBUUID(string: "FFE1"),
        CBUUID(string: "2AF1"),
        CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")
    ]

    private static let knownNotifyUUIDs: Set<CBUUID> = [
        CBUUID(string: "FFF1"),
        CBUUID(string: "FFE1"),
        CBUUID(string: "2AF0"),
        CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")
    ]

    private let lastDeviceKey = "AltoOBD.LastConnectedPeripheralUUID"

    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var responseBuffer = ""
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var pendingTimeoutWorkItem: DispatchWorkItem?
    private let commandLock = NSLock()
    private var isCommandInFlight = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scanning & Connection

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            state = .bluetoothUnavailable("Turn on Bluetooth in iOS Settings")
            return
        }
        discoveredDevices.removeAll()
        state = .scanning
        // Scan with nil services so adapters advertising custom/generic names are still discovered
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        appendLog("BLE scan started")
    }

    func stopScanning() {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        if case .scanning = state {
            state = .disconnected
        }
    }

    func connect(to device: DiscoveredOBDDevice) {
        stopScanning()
        activePeripheral = device.peripheral
        activePeripheral?.delegate = self
        writeCharacteristic = nil
        notifyCharacteristic = nil
        state = .connecting(device.name)
        UserDefaults.standard.set(device.id.uuidString, forKey: lastDeviceKey)
        appendLog("Connecting to \(device.name)...")
        centralManager.connect(device.peripheral, options: nil)
    }

    func reconnectLastDevice() {
        guard centralManager.state == .poweredOn,
              let uuidString = UserDefaults.standard.string(forKey: lastDeviceKey),
              let uuid = UUID(uuidString: uuidString) else {
            startScanning()
            return
        }
        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = known.first {
            let name = peripheral.name ?? "Saved OBD Adapter"
            let device = DiscoveredOBDDevice(id: peripheral.identifier, name: name, rssi: -60, peripheral: peripheral)
            connect(to: device)
        } else {
            startScanning()
        }
    }

    func disconnect() {
        stopScanning()
        failPendingCommand(OBDCommandError.notConnected)
        if let peripheral = activePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        activePeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        state = .disconnected
        appendLog("Disconnected")
    }

    // MARK: - Command Sending (Async Serialized)

    /// Sends an AT or OBD-II command (e.g., "ATZ", "010C") and awaits the ELM327 `>` prompt.
    @MainActor
    func sendCommand(_ command: String, timeout: TimeInterval = 2.5) async throws -> String {
        guard let peripheral = activePeripheral,
              let writeChar = writeCharacteristic else {
            throw OBDCommandError.notConnected
        }

        // Wait briefly if another command is still finishing
        while isCommandInFlight {
            try await Task.sleep(nanoseconds: 15_000_000)
        }

        isCommandInFlight = true
        responseBuffer = ""
        defer { isCommandInFlight = false }

        let payloadString = command.trimmingCharacters(in: .whitespacesAndNewlines) + "\r"
        guard let data = payloadString.data(using: .ascii) else {
            throw OBDCommandError.writeFailed("Invalid ASCII command")
        }

        appendLog("> \(command)")

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let partial = self.responseBuffer
                self.pendingContinuation?.resume(throwing: OBDCommandError.timeout(command))
                self.pendingContinuation = nil
                self.appendLog("! Timeout on \(command) (partial: \(partial))")
            }
            self.pendingTimeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)

            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse)
                ? .withoutResponse
                : .withResponse
            peripheral.writeValue(data, for: writeChar, type: writeType)
        }
    }

    /// Runs the standard ELM327 initialization handshake optimized for Suzuki EOBD ECUs.
    @MainActor
    func initializeELM327() async throws {
        let name = activePeripheral?.name ?? "OBD Adapter"
        state = .initializingELM(name)

        // Reset ELM327 chip
        let resetResp = try await sendCommand("ATZ", timeout: 4.0)
        elmVersion = ELM327Parser.cleanLines(from: resetResp).first ?? "ELM327 BLE"

        _ = try? await sendCommand("ATE0", timeout: 2.0) // Echo off
        _ = try? await sendCommand("ATL0", timeout: 2.0) // Linefeeds off
        _ = try? await sendCommand("ATS0", timeout: 2.0) // Spaces off (faster throughput on BLE)
        _ = try? await sendCommand("ATH0", timeout: 2.0) // Headers off
        _ = try? await sendCommand("ATSP0", timeout: 2.0) // Auto-detect ECU protocol (CAN / KWP2000 / ISO9141)

        // Probe ECU with 0100 to wake up protocol auto-detection
        _ = try? await sendCommand("0100", timeout: 5.0)

        if let protoResp = try? await sendCommand("ATDP", timeout: 2.0) {
            detectedProtocolName = ELM327Parser.cleanLines(from: protoResp).first ?? "Auto"
        }

        state = .connected(name)
        appendLog("Ready (\(elmVersion) | \(detectedProtocolName))")
    }

    private func completePendingCommandIfReady() {
        guard responseBuffer.contains(">") else { return }
        let fullResponse = responseBuffer
        responseBuffer = ""
        pendingTimeoutWorkItem?.cancel()
        pendingTimeoutWorkItem = nil
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            appendLog("< \(fullResponse.replacingOccurrences(of: "\r", with: " ").trimmingCharacters(in: .whitespaces))")
            continuation.resume(returning: fullResponse)
        }
    }

    private func failPendingCommand(_ error: Error) {
        pendingTimeoutWorkItem?.cancel()
        pendingTimeoutWorkItem = nil
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            continuation.resume(throwing: error)
        }
    }

    private func appendLog(_ entry: String) {
        commandLog.append(entry)
        if commandLog.count > 120 {
            commandLog.removeFirst(commandLog.count - 120)
        }
    }

    /// Heuristic to prioritize likely OBD-II BLE adapters at the top of the scan list.
    static func isLikelyOBDAdapter(name: String, serviceUUIDs: [CBUUID]?) -> Bool {
        let lower = name.lowercased()
        let keywords = ["obd", "elm", "vgate", "veepeak", "vlink", "v-link", "icar", "carista", "lelink", "konnwei", "ios-vlink", "ble", "ecu"]
        if keywords.contains(where: { lower.contains($0) }) { return true }
        if let uuids = serviceUUIDs, uuids.contains(where: { knownServiceUUIDs.contains($0) }) {
            return true
        }
        return false
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEOBDManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .bluetoothUnavailable = state {
                state = .disconnected
            }
        case .poweredOff:
            state = .bluetoothUnavailable("Bluetooth is turned off")
        case .unauthorized:
            state = .bluetoothUnavailable("Bluetooth permission denied")
        case .unsupported:
            state = .bluetoothUnavailable("Bluetooth LE not supported on this device")
        default:
            state = .bluetoothUnavailable("Checking Bluetooth…")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? ""
        let trimmed = advertisedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let rssiVal = RSSI.intValue == 127 ? -99 : RSSI.intValue
        let item = DiscoveredOBDDevice(id: peripheral.identifier, name: trimmed, rssi: rssiVal, peripheral: peripheral)

        if let existingIndex = discoveredDevices.firstIndex(where: { $0.id == item.id }) {
            discoveredDevices[existingIndex] = item
        } else {
            discoveredDevices.append(item)
        }

        // Sort likely OBD adapters first, then by strongest signal
        discoveredDevices.sort { lhs, rhs in
            let lLikely = Self.isLikelyOBDAdapter(name: lhs.name, serviceUUIDs: serviceUUIDs)
            let rLikely = Self.isLikelyOBDAdapter(name: rhs.name, serviceUUIDs: nil)
            if lLikely != rLikely { return lLikely }
            return lhs.rssi > rhs.rssi
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected GATT, discovering services…")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .error(error?.localizedDescription ?? "Failed to connect")
        appendLog("Connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        failPendingCommand(OBDCommandError.notConnected)
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if let error {
            state = .error("Disconnected: \(error.localizedDescription)")
        } else {
            state = .disconnected
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEOBDManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .error("Service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            state = .error("No BLE UART services found. Ensure your adapter is BLE 4.0+.")
            return
        }

        // Prioritize known OBD services first, else discover all
        let matching = services.filter { Self.knownServiceUUIDs.contains($0.uuid) }
        let targets = matching.isEmpty ? services : matching
        for service in targets {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }

        for char in characteristics {
            if Self.knownWriteUUIDs.contains(char.uuid) ||
                (writeCharacteristic == nil && (char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse))) {
                writeCharacteristic = char
            }
            if Self.knownNotifyUUIDs.contains(char.uuid) ||
                (notifyCharacteristic == nil && (char.properties.contains(.notify) || char.properties.contains(.indicate))) {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        if writeCharacteristic != nil && notifyCharacteristic != nil,
           case .connecting = state {
            Task { @MainActor in
                do {
                    try await self.initializeELM327()
                } catch {
                    self.state = .error("ELM327 init failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if let chunk = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) {
            responseBuffer.append(chunk)
            completePendingCommandIfReady()
        }
    }
}
