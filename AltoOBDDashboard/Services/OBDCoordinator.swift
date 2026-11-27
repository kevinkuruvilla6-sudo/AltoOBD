import Foundation
import Combine
import UIKit

/// High-level coordinator bridging `BLEOBDManager`, `ELM327Parser`, `TripStore`, `VehicleProfile`,
/// and a realistic Suzuki Alto 800 UK Simulator mode for testing without being plugged into the car.
@MainActor
final class OBDCoordinator: ObservableObject {
    @Published var profile: VehicleProfile {
        didSet {
            saveProfile()
            UIApplication.shared.isIdleTimerDisabled = profile.keepScreenAwake
        }
    }

    @Published var telemetry = TelemetrySnapshot()
    @Published var storedDTCs: [DiagnosticCode] = []
    @Published var pendingDTCs: [DiagnosticCode] = []
    @Published var supportedPIDs: Set<UInt8> = []
    @Published var isDemoMode: Bool = false
    @Published var isScanningDTCs: Bool = false
    @Published var lastDiagnosticMessage: String?
    @Published var terminalOutput: [String] = [
        "Suzuki Alto 800 OBD-II Terminal Ready.",
        "Connect a BLE OBD adapter or enable Demo Mode."
    ]

    let bleManager = BLEOBDManager()
    let tripStore = TripStore()

    private let profileKey = "AltoOBD.VehicleProfile.v1"
    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var smoothedKmPerLiter: Double?
    private var demoElapsedSeconds: Double = 0
    private var demoInjectedFault: Bool = false

    init() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let saved = try? JSONDecoder().decode(VehicleProfile.self, from: data) {
            self.profile = saved
        } else {
            self.profile = .alto800CruzUK
        }

        UIApplication.shared.isIdleTimerDisabled = profile.keepScreenAwake

        // Forward BLE state changes to start/stop live ECU polling automatically
        bleManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.objectWillChange.send()
                if case .connected = newState {
                    self.isDemoMode = false
                    self.startLivePolling()
                } else if !self.isDemoMode {
                    self.stopPolling()
                }
            }
            .store(in: &cancellables)

        bleManager.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        bleManager.$commandLog
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isLiveOrSimulated: Bool {
        isDemoMode || bleManager.state.isConnected
    }

    var connectionBadgeText: String {
        if isDemoMode { return "Alto 800 Demo" }
        return bleManager.state.label
    }

    /// Estimated remaining driving range based on fuel level (if supported) or full tank estimate.
    var estimatedRangeKm: Double? {
        guard let avgKpl = tripStore.currentTrip.averageKmPerLiter ?? telemetry.smoothedKmPerLiter else {
            return nil
        }
        let remainingFraction = (telemetry.fuelTankLevelPercent ?? 65.0) / 100.0
        return max(0, profile.fuelTankLiters * remainingFraction * avgKpl)
    }

    // MARK: - Demo Mode (Suzuki Alto 800 UK Drive Cycle)

    func setDemoMode(_ enabled: Bool) {
        if enabled {
            bleManager.disconnect()
            isDemoMode = true
            demoElapsedSeconds = 0
            supportedPIDs = [0x01, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x1F, 0x2F, 0x31, 0x42]
            startDemoPolling()
        } else {
            isDemoMode = false
            stopPolling()
            telemetry = TelemetrySnapshot()
        }
    }

    func toggleSimulatedFault() {
        demoInjectedFault.toggle()
        if demoInjectedFault {
            storedDTCs = [DiagnosticCode(code: "P0171", status: .stored)]
            pendingDTCs = [DiagnosticCode(code: "P0133", status: .pending)]
            telemetry.milOn = true
            telemetry.dtcCount = 1
            lastDiagnosticMessage = "Simulated fault P0171 (System Too Lean) injected."
        } else {
            storedDTCs = []
            pendingDTCs = []
            telemetry.milOn = false
            telemetry.dtcCount = 0
            lastDiagnosticMessage = "Simulated faults cleared."
        }
    }

    private func startDemoPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isDemoMode {
                self.stepAlto800Simulation(dt: 0.35)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    /// Simulates a realistic UK town & B-road journey in a 796cc 3-cylinder Suzuki Alto 800 (MAP-only ECU).
    private func stepAlto800Simulation(dt: Double) {
        demoElapsedSeconds += dt
        let t = demoElapsedSeconds

        // Repeating 60-second UK drive cycle: traffic lights -> town 30mph -> A-road 50mph -> coasting -> stop
        let phase = t.truncatingRemainder(dividingBy: 60.0)
        let targetSpeedKmh: Double
        let throttle: Double
        if phase < 6 {
            targetSpeedKmh = 0 // Idle at traffic lights
            throttle = 11.0
        } else if phase < 18 {
            targetSpeedKmh = 48.0 * ((phase - 6) / 12.0) // Accelerate to ~30 mph
            throttle = 38.0 + sin(t * 2.5) * 6.0
        } else if phase < 32 {
            targetSpeedKmh = 48.0 + sin(t * 0.7) * 4.0 // Cruise 30 mph
            throttle = 22.0 + sin(t * 0.8) * 3.0
        } else if phase < 44 {
            targetSpeedKmh = 48.0 + 32.0 * ((phase - 32) / 12.0) // Accelerate onto 50 mph UK A-road
            throttle = 52.0 + sin(t * 1.9) * 8.0
        } else if phase < 53 {
            targetSpeedKmh = 80.0 + sin(t * 0.5) * 3.0 // Cruise 50 mph in 5th gear
            throttle = 28.0 + sin(t * 0.9) * 3.0
        } else {
            targetSpeedKmh = max(0, 80.0 * (1.0 - (phase - 53) / 7.0)) // Decelerate to stop
            throttle = 11.0
        }

        // Simulate 5-speed gearbox RPM ratios for Alto 800
        let rpm: Double
        if targetSpeedKmh < 2 {
            rpm = 850 + sin(t * 4.0) * 18
        } else if targetSpeedKmh < 22 {
            rpm = 1200 + targetSpeedKmh * 115
        } else if targetSpeedKmh < 40 {
            rpm = 1100 + targetSpeedKmh * 72
        } else if targetSpeedKmh < 60 {
            rpm = 1000 + targetSpeedKmh * 52
        } else {
            rpm = 950 + targetSpeedKmh * 38
        }

        // Simulate MAP (kPa) proportional to throttle/load (typical 28 kPa idle, 55-85 kPa cruise/accel)
        let mapKpa = min(98.0, max(24.0, 26.0 + (throttle - 10.0) * 1.25))
        let load = min(95.0, max(16.0, (mapKpa / 100.0) * 88.0))
        // Gradual coolant warmup from 62°C to 89°C operating temp
        let coolant = min(89.5, 62.0 + t * 0.45) + sin(t * 0.2) * 1.2
        let iat = 18.0 + sin(t * 0.1) * 2.0
        let voltage = 14.15 + sin(t * 1.3) * 0.08
        let stft = sin(t * 0.9) * 2.4
        let ltft = 1.6

        let fuel = ELM327Parser.estimateFuelConsumption(
            speedKmh: targetSpeedKmh,
            rpm: rpm,
            mafGramsPerSec: nil, // Alto 800 F8D uses MAP Speed-Density!
            mapKpa: mapKpa,
            iatCelsius: iat,
            stftPercent: stft,
            ltftPercent: ltft,
            profile: profile
        )

        updateSmoothedEconomy(with: fuel.instantKmPerLiter)

        var snap = telemetry
        snap.timestamp = Date()
        snap.rpm = rpm
        snap.speedKmh = targetSpeedKmh
        snap.engineLoadPercent = load
        snap.throttlePositionPercent = throttle
        snap.coolantTempCelsius = coolant
        snap.intakeAirTempCelsius = iat
        snap.batteryVoltage = voltage
        snap.manifoldPressureKpa = mapKpa
        snap.mafGramsPerSec = nil
        snap.shortTermFuelTrimPercent = stft
        snap.longTermFuelTrimPercent = ltft
        snap.timingAdvanceDegrees = 12.0 + (rpm / 400.0)
        snap.fuelTankLevelPercent = max(5.0, 68.0 - (tripStore.currentTrip.fuelUsedLiters / profile.fuelTankLiters) * 100.0)
        snap.runTimeSeconds = Int(t)
        snap.distanceSinceCodesClearedKm = 1420 + tripStore.currentTrip.distanceKm
        snap.milOn = demoInjectedFault
        snap.dtcCount = demoInjectedFault ? 1 : 0
        snap.fuelFlowLitersPerHour = fuel.fuelLitersPerHour
        snap.instantKmPerLiter = fuel.instantKmPerLiter
        snap.smoothedKmPerLiter = smoothedKmPerLiter
        snap.fuelSource = fuel.source

        telemetry = snap
        tripStore.recordTelemetry(snap, profile: profile)
    }

    // MARK: - Live BLE ECU Polling

    private func startLivePolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.probeSupportedPIDs()

            var cycleCount = 0
            while !Task.isCancelled && self.bleManager.state.isConnected {
                // Fast tier (~3-5 Hz depending on ECU/KWP2000 vs CAN speed):
                // RPM, Speed, Throttle, and either MAF or MAP
                await self.pollPID(.engineRPM)
                await self.pollPID(.vehicleSpeed)

                if self.isPIDSupported(.mafAirFlowRate) {
                    await self.pollPID(.mafAirFlowRate)
                }
                if self.isPIDSupported(.intakeManifoldPressure) || !self.isPIDSupported(.mafAirFlowRate) {
                    await self.pollPID(.intakeManifoldPressure)
                }
                if self.isPIDSupported(.throttlePosition) {
                    await self.pollPID(.throttlePosition)
                }
                if self.isPIDSupported(.calculatedEngineLoad) {
                    await self.pollPID(.calculatedEngineLoad)
                }

                // Medium tier (every 4th cycle): Coolant, IAT, Fuel Trims, Battery Voltage
                if cycleCount % 4 == 0 {
                    await self.pollPID(.coolantTemperature)
                    await self.pollPID(.intakeAirTemperature)
                    await self.pollBatteryVoltage()
                    if self.isPIDSupported(.shortTermFuelTrimB1) {
                        await self.pollPID(.shortTermFuelTrimB1)
                    }
                    if self.isPIDSupported(.longTermFuelTrimB1) {
                        await self.pollPID(.longTermFuelTrimB1)
                    }
                }

                // Slow tier (every 12th cycle): MIL status, Timing, Run time, Fuel Level
                if cycleCount % 12 == 0 {
                    await self.pollMonitorStatus()
                    if self.isPIDSupported(.timingAdvance) {
                        await self.pollPID(.timingAdvance)
                    }
                    if self.isPIDSupported(.fuelTankLevel) {
                        await self.pollPID(.fuelTankLevel)
                    }
                    if self.isPIDSupported(.runTimeSinceStart) {
                        await self.pollPID(.runTimeSinceStart)
                    }
                    if self.isPIDSupported(.distanceSinceCodesCleared) {
                        await self.pollPID(.distanceSinceCodesCleared)
                    }
                }

                // Recompute live fuel consumption & integrate trip
                self.recalculateDerivedFuelAndTrip()
                cycleCount += 1

                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func probeSupportedPIDs() async {
        var found: Set<UInt8> = []
        if let r0 = try? await bleManager.sendCommand("0100", timeout: 3.0) {
            found.formUnion(ELM327Parser.decodeSupportedPIDs(from: r0, basePID: .supportedPIDs01to20))
        }
        if found.contains(0x20), let r20 = try? await bleManager.sendCommand("0120", timeout: 3.0) {
            found.formUnion(ELM327Parser.decodeSupportedPIDs(from: r20, basePID: .supportedPIDs21to40))
        }
        if found.contains(0x40), let r40 = try? await bleManager.sendCommand("0140", timeout: 3.0) {
            found.formUnion(ELM327Parser.decodeSupportedPIDs(from: r40, basePID: .supportedPIDs41to60))
        }
        supportedPIDs = found
    }

    private func isPIDSupported(_ pid: OBDPID) -> Bool {
        // If ECU didn't return bitmask, optimistically allow polling common PIDs
        if supportedPIDs.isEmpty { return true }
        return supportedPIDs.contains(pid.rawValue)
    }

    private func pollPID(_ pid: OBDPID) async {
        guard let raw = try? await bleManager.sendCommand(pid.command, timeout: 1.8),
              let bytes = ELM327Parser.extractMode01DataBytes(from: raw, pid: pid),
              let value = ELM327Parser.decodeMode01Value(pid: pid, bytes: bytes) else {
            return
        }

        switch pid {
        case .engineRPM: telemetry.rpm = value
        case .vehicleSpeed: telemetry.speedKmh = value
        case .calculatedEngineLoad: telemetry.engineLoadPercent = value
        case .coolantTemperature: telemetry.coolantTempCelsius = value
        case .shortTermFuelTrimB1: telemetry.shortTermFuelTrimPercent = value
        case .longTermFuelTrimB1: telemetry.longTermFuelTrimPercent = value
        case .intakeManifoldPressure: telemetry.manifoldPressureKpa = value
        case .timingAdvance: telemetry.timingAdvanceDegrees = value
        case .intakeAirTemperature: telemetry.intakeAirTempCelsius = value
        case .mafAirFlowRate: telemetry.mafGramsPerSec = value
        case .throttlePosition: telemetry.throttlePositionPercent = value
        case .runTimeSinceStart: telemetry.runTimeSeconds = Int(value)
        case .fuelTankLevel: telemetry.fuelTankLevelPercent = value
        case .distanceSinceCodesCleared: telemetry.distanceSinceCodesClearedKm = value
        case .controlModuleVoltage: telemetry.batteryVoltage = value
        default: break
        }
    }

    private func pollBatteryVoltage() async {
        if isPIDSupported(.controlModuleVoltage),
           let raw = try? await bleManager.sendCommand(OBDPID.controlModuleVoltage.command, timeout: 1.8),
           let bytes = ELM327Parser.extractMode01DataBytes(from: raw, pid: .controlModuleVoltage),
           let volts = ELM327Parser.decodeMode01Value(pid: .controlModuleVoltage, bytes: bytes) {
            telemetry.batteryVoltage = volts
            return
        }
        // Fallback to ELM327 hardware voltage pin reading (`ATRV`), which works on almost all cars!
        if let raw = try? await bleManager.sendCommand("ATRV", timeout: 1.8),
           let volts = ELM327Parser.decodeBatteryVoltage(from: raw) {
            telemetry.batteryVoltage = volts
        }
    }

    private func pollMonitorStatus() async {
        guard let raw = try? await bleManager.sendCommand("0101", timeout: 2.0),
              let status = ELM327Parser.decodeMonitorStatus(from: raw) else {
            return
        }
        telemetry.milOn = status.milOn
        telemetry.dtcCount = status.dtcCount
    }

    private func recalculateDerivedFuelAndTrip() {
        let fuel = ELM327Parser.estimateFuelConsumption(
            speedKmh: telemetry.speedKmh,
            rpm: telemetry.rpm,
            mafGramsPerSec: telemetry.mafGramsPerSec,
            mapKpa: telemetry.manifoldPressureKpa,
            iatCelsius: telemetry.intakeAirTempCelsius,
            stftPercent: telemetry.shortTermFuelTrimPercent,
            ltftPercent: telemetry.longTermFuelTrimPercent,
            profile: profile
        )
        updateSmoothedEconomy(with: fuel.instantKmPerLiter)
        telemetry.timestamp = Date()
        telemetry.fuelFlowLitersPerHour = fuel.fuelLitersPerHour
        telemetry.instantKmPerLiter = fuel.instantKmPerLiter
        telemetry.smoothedKmPerLiter = smoothedKmPerLiter
        telemetry.fuelSource = fuel.source

        tripStore.recordTelemetry(telemetry, profile: profile)
    }

    private func updateSmoothedEconomy(with instant: Double?) {
        guard let instant, instant.isFinite else {
            smoothedKmPerLiter = nil
            return
        }
        if let prev = smoothedKmPerLiter {
            // Smooth exponential moving average so live MPG gauge is readable while responsive
            smoothedKmPerLiter = (prev * 0.72) + (instant * 0.28)
        } else {
            smoothedKmPerLiter = instant
        }
    }

    // MARK: - Diagnostics (Read / Clear DTCs & Raw Terminal)

    func scanDiagnosticCodes() async {
        isScanningDTCs = true
        defer { isScanningDTCs = false }

        if isDemoMode {
            try? await Task.sleep(nanoseconds: 500_000_000)
            lastDiagnosticMessage = storedDTCs.isEmpty
                ? "Demo Scan Complete: No active fault codes found."
                : "Demo Scan Complete: \(storedDTCs.count) stored, \(pendingDTCs.count) pending."
            return
        }

        guard bleManager.state.isConnected else {
            lastDiagnosticMessage = "Connect to your BLE OBD adapter first."
            return
        }

        do {
            let storedRaw = try await bleManager.sendCommand("03", timeout: 4.0)
            storedDTCs = ELM327Parser.decodeDTCs(from: storedRaw, status: .stored)

            let pendingRaw = try? await bleManager.sendCommand("07", timeout: 3.5)
            pendingDTCs = pendingRaw.map { ELM327Parser.decodeDTCs(from: $0, status: .pending) } ?? []

            await pollMonitorStatus()
            if storedDTCs.isEmpty && pendingDTCs.isEmpty {
                lastDiagnosticMessage = "ECU Scan Complete: No fault codes found."
            } else {
                lastDiagnosticMessage = "Found \(storedDTCs.count) stored and \(pendingDTCs.count) pending code(s)."
            }
        } catch {
            lastDiagnosticMessage = "Scan failed: \(error.localizedDescription)"
        }
    }

    func clearDiagnosticCodes() async {
        if isDemoMode {
            demoInjectedFault = false
            storedDTCs = []
            pendingDTCs = []
            telemetry.milOn = false
            telemetry.dtcCount = 0
            lastDiagnosticMessage = "Demo fault codes cleared."
            return
        }

        guard bleManager.state.isConnected else {
            lastDiagnosticMessage = "Not connected to OBD adapter."
            return
        }

        do {
            _ = try await bleManager.sendCommand("04", timeout: 4.0)
            storedDTCs = []
            pendingDTCs = []
            telemetry.milOn = false
            telemetry.dtcCount = 0
            lastDiagnosticMessage = "Mode 04 clear command sent. Re-scan after ignition cycle to confirm."
        } catch {
            lastDiagnosticMessage = "Clear failed: \(error.localizedDescription)"
        }
    }

    func sendTerminalCommand(_ cmd: String) async {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        terminalOutput.append("> \(trimmed)")

        if isDemoMode {
            let simulatedReply: String
            switch trimmed {
            case "ATI": simulatedReply = "ELM327 v1.5 (Alto 800 Demo)"
            case "ATRV": simulatedReply = String(format: "%.1fV", telemetry.batteryVoltage ?? 14.1)
            case "ATDP": simulatedReply = "AUTO, ISO 15765-4 (CAN 11/500)"
            case "010C": simulatedReply = "41 0C 0D 48"
            case "0105": simulatedReply = "41 05 81"
            default: simulatedReply = "OK (Demo Mode)"
            }
            terminalOutput.append("< \(simulatedReply)")
            return
        }

        do {
            let resp = try await bleManager.sendCommand(trimmed, timeout: 3.5)
            let cleaned = ELM327Parser.cleanLines(from: resp).joined(separator: " | ")
            terminalOutput.append("< \(cleaned.isEmpty ? "OK" : cleaned)")
        } catch {
            terminalOutput.append("! \(error.localizedDescription)")
        }
    }

    private func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
}
