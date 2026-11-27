import Foundation

/// Pure, stateless parser and fuel-economy math engine for ELM327 OBD-II responses.
/// Designed specifically to handle both MAF-equipped ECUs and MAP-only ECUs like the Suzuki Alto 800 (F8D).
enum ELM327Parser {

    // MARK: - Cleaning & Hex Extraction

    /// Removes echo lines, whitespace, prompt characters (`>`), and status banners from raw ELM327 responses.
    static func cleanLines(from raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let upper = line.uppercased()
                if upper == ">" || upper == "OK" { return false }
                if upper.contains("SEARCHING") || upper.contains("BUS INIT") { return false }
                return true
            }
            .map { $0.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces) }
    }

    static func isErrorResponse(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        let tokens = ["NO DATA", "UNABLE TO CONNECT", "ERROR", "STOPPED", "CAN ERROR", "BUS ERROR", "?"]
        return tokens.contains { upper.contains($0) }
    }

    /// Parses hex bytes for a Mode 01 PID response (e.g. "41 0C 0F A0" or "410C0FA0" or CAN "7E8 04 41 0C 0F A0").
    static func extractMode01DataBytes(from raw: String, pid: OBDPID) -> [UInt8]? {
        guard !isErrorResponse(raw) else { return nil }
        let pidHex = String(format: "%02X", pid.rawValue)

        for line in cleanLines(from: raw) {
            let stripped = line.replacingOccurrences(of: " ", with: "").uppercased()
            // Ignore lines that aren't valid hex
            guard stripped.count >= 4, stripped.allSatisfy({ $0.isHexDigit }) else { continue }

            // Look for "41<PID>" marker (handles both headerless and CAN-headered responses)
            let marker = "41\(pidHex)"
            guard let range = stripped.range(of: marker) else { continue }
            let payloadHex = String(stripped[range.upperBound...])
            let bytes = hexStringToBytes(payloadHex)
            if bytes.count >= pid.expectedByteCount {
                return Array(bytes.prefix(pid.expectedByteCount))
            }
        }
        return nil
    }

    static func hexStringToBytes(_ hex: String) -> [UInt8] {
        let chars = Array(hex)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i + 1 < chars.count {
            let pair = String(chars[i...i + 1])
            if let byte = UInt8(pair, radix: 16) {
                bytes.append(byte)
            }
            i += 2
        }
        return bytes
    }

    // MARK: - Mode 01 PID Value Decoding

    /// Decodes a standard Mode 01 PID into its metric physical value.
    static func decodeMode01Value(pid: OBDPID, bytes: [UInt8]) -> Double? {
        guard bytes.count >= pid.expectedByteCount else { return nil }
        let a = Double(bytes[0])
        let b = bytes.count > 1 ? Double(bytes[1]) : 0.0

        switch pid {
        case .calculatedEngineLoad, .throttlePosition, .fuelTankLevel:
            return (a * 100.0) / 255.0
        case .coolantTemperature, .intakeAirTemperature:
            return a - 40.0
        case .shortTermFuelTrimB1, .longTermFuelTrimB1:
            return ((a - 128.0) * 100.0) / 128.0
        case .intakeManifoldPressure:
            return a // kPa
        case .engineRPM:
            return ((a * 256.0) + b) / 4.0
        case .vehicleSpeed:
            return a // km/h
        case .timingAdvance:
            return (a / 2.0) - 64.0
        case .mafAirFlowRate:
            return ((a * 256.0) + b) / 100.0 // g/s
        case .runTimeSinceStart, .distanceWithMILOn, .distanceSinceCodesCleared:
            return (a * 256.0) + b
        case .controlModuleVoltage:
            return ((a * 256.0) + b) / 1000.0 // Volts
        default:
            return nil
        }
    }

    /// Parses Mode 01 PID 01 (Monitor Status) -> (milOn: Bool, dtcCount: Int)
    static func decodeMonitorStatus(from raw: String) -> (milOn: Bool, dtcCount: Int)? {
        guard let bytes = extractMode01DataBytes(from: raw, pid: .monitorStatus), !bytes.isEmpty else {
            return nil
        }
        let first = bytes[0]
        let milOn = (first & 0x80) != 0
        let count = Int(first & 0x7F)
        return (milOn, count)
    }

    /// Parses supported PIDs bitmask from `0100`, `0120`, or `0140`.
    static func decodeSupportedPIDs(from raw: String, basePID: OBDPID) -> Set<UInt8> {
        guard let bytes = extractMode01DataBytes(from: raw, pid: basePID), bytes.count == 4 else {
            return []
        }
        var supported: Set<UInt8> = []
        let mask: UInt32 = (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
        for bit in 0..<32 {
            if (mask & (1 << (31 - bit))) != 0 {
                let pidValue = basePID.rawValue + UInt8(bit + 1)
                supported.insert(pidValue)
            }
        }
        return supported
    }

    /// Parses ELM327 `ATRV` voltage output such as `"14.2V"` or `"12.6V"`.
    static func decodeBatteryVoltage(from raw: String) -> Double? {
        for line in cleanLines(from: raw) {
            let cleaned = line.uppercased()
                .replacingOccurrences(of: "V", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(cleaned), value >= 5.0 && value <= 20.0 {
                return value
            }
        }
        return nil
    }

    // MARK: - Mode 03 & Mode 07 DTC Decoding

    /// Decodes Diagnostic Trouble Codes from Mode 03 (`43 ...`) or Mode 07 (`47 ...`).
    /// Supports both ISO 9141/KWP2000 (2-byte pairs immediately after `43`) and ISO 15765 CAN (`43 <count> <pairs>`).
    static func decodeDTCs(from raw: String, status: DTCStatus) -> [DiagnosticCode] {
        guard !isErrorResponse(raw) else { return [] }
        let modeMarker = status == .stored ? "43" : "47"
        var foundCodes: [String] = []

        for line in cleanLines(from: raw) {
            let stripped = line.replacingOccurrences(of: " ", with: "").uppercased()
            // Handle CAN multi-frame prefix like "0:430201710301" or "1:..."
            let normalized: String
            if let colonIdx = stripped.firstIndex(of: ":") {
                normalized = String(stripped[stripped.index(after: colonIdx)...])
            } else {
                normalized = stripped
            }

            guard normalized.allSatisfy({ $0.isHexDigit }), let range = normalized.range(of: modeMarker) else {
                continue
            }
            let payload = String(normalized[range.upperBound...])
            var bytes = hexStringToBytes(payload)

            // Detect CAN count byte: if byte count is odd (e.g. 43 02 01 71 03 01 -> 5 bytes after 43),
            // or if the first byte equals the exact count of non-zero 2-byte pairs following it.
            if bytes.count % 2 == 1 && bytes.count >= 3 {
                bytes.removeFirst()
            } else if bytes.count >= 3, bytes[0] > 0, Int(bytes[0]) * 2 == bytes.count - 1 {
                bytes.removeFirst()
            }

            var idx = 0
            while idx + 1 < bytes.count {
                let b1 = bytes[idx]
                let b2 = bytes[idx + 1]
                idx += 2
                // 0x00 0x00 is padding
                if b1 == 0 && b2 == 0 { continue }
                let code = formatDTC(highByte: b1, lowByte: b2)
                if !foundCodes.contains(code) {
                    foundCodes.append(code)
                }
            }
        }

        return foundCodes.map { DiagnosticCode(code: $0, status: status) }
    }

    static func formatDTC(highByte: UInt8, lowByte: UInt8) -> String {
        let prefixIndex = (highByte & 0xC0) >> 6
        let prefixChar: String
        switch prefixIndex {
        case 0: prefixChar = "P"
        case 1: prefixChar = "C"
        case 2: prefixChar = "B"
        default: prefixChar = "U"
        }
        let d1 = (highByte & 0x30) >> 4
        let d2 = highByte & 0x0F
        let d3 = (lowByte & 0xF0) >> 4
        let d4 = lowByte & 0x0F
        return String(format: "%@%X%X%X%X", prefixChar, d1, d2, d3, d4)
    }

    // MARK: - Fuel Flow & Mileage Math (MAF + Speed-Density MAP for Alto 800)

    enum FuelCalcSource: String, Codable {
        case mafSensor = "MAF Sensor"
        case speedDensityMAP = "MAP Speed-Density"
        case unavailable = "Waiting for ECU"
    }

    struct FuelEstimate {
        let mafGramsPerSecond: Double
        let fuelLitersPerHour: Double
        let instantKmPerLiter: Double?
        let source: FuelCalcSource
    }

    /// Computes instantaneous fuel consumption (L/h) and mileage (km/L).
    /// Automatically uses real MAF if the ECU provides it; otherwise falls back to Speed-Density
    /// using MAP, IAT, RPM, Fuel Trims, and the Suzuki Alto 800's 0.796L displacement.
    static func estimateFuelConsumption(
        speedKmh: Double,
        rpm: Double,
        mafGramsPerSec: Double?,
        mapKpa: Double?,
        iatCelsius: Double?,
        stftPercent: Double?,
        ltftPercent: Double?,
        profile: VehicleProfile
    ) -> FuelEstimate {
        let airFuelRatio = 14.7       // Stoichiometric ratio for petrol (E5/E10 ~14.4-14.7)
        let petrolDensityGPerL = 745.0 // g/L at ~15°C UK ambient

        var resolvedMAF: Double?
        var source: FuelCalcSource = .unavailable

        if let maf = mafGramsPerSec, maf > 0.05 {
            resolvedMAF = maf
            source = .mafSensor
        } else if let map = mapKpa, rpm > 100 {
            // Ideal gas law Speed-Density estimation for 4-stroke engine:
            // IMAP = (RPM * MAP) / IAT_K
            // MAF(g/s) = (IMAP / 120) * VE * Displacement(L) * (M_air / R)
            let iatKelvin = max((iatCelsius ?? 25.0) + 273.15, 220.0)
            let imap = (rpm * map) / iatKelvin
            let molarMassAir = 28.97 // g/mol
            let gasConstant = 8.314  // J/(mol*K)
            var mafEst = (imap / 120.0) * profile.volumetricEfficiency * profile.displacementLiters * (molarMassAir / gasConstant)

            // Apply short & long term fuel trim correction if available (clamped for sanity)
            let trimPercent = (stftPercent ?? 0.0) + (ltftPercent ?? 0.0)
            let trimFactor = max(0.75, min(1.30, 1.0 + (trimPercent / 100.0)))
            mafEst *= trimFactor

            resolvedMAF = max(mafEst, 0.0)
            source = .speedDensityMAP
        }

        guard let maf = resolvedMAF, maf > 0.01 else {
            return FuelEstimate(mafGramsPerSecond: 0, fuelLitersPerHour: 0, instantKmPerLiter: nil, source: .unavailable)
        }

        // Fuel Flow (L/h) = (MAF [g/s] * 3600 [s/h]) / (AFR * petrolDensity [g/L])
        let litersPerHour = (maf * 3600.0) / (airFuelRatio * petrolDensityGPerL)

        // Instant mileage (km/L) is only meaningful when the car is moving (> 2 km/h)
        let kmPerLiter: Double?
        if speedKmh > 2.0 && litersPerHour > 0.05 {
            kmPerLiter = speedKmh / litersPerHour
        } else {
            kmPerLiter = nil
        }

        return FuelEstimate(
            mafGramsPerSecond: maf,
            fuelLitersPerHour: litersPerHour,
            instantKmPerLiter: kmPerLiter,
            source: source
        )
    }

    // MARK: - Exhaust CO2 & Combustion Cleanliness / Smoke Risk Estimation

    enum ExhaustCleanliness: String, Codable {
        case clean = "Clean Burn"
        case warmingUp = "Cold Warmup"
        case elevated = "Elevated Output"
        case highRisk = "Rich / High Risk"
    }

    struct EmissionsEstimate {
        /// Petrol stoichiometric CO2 factor: ~2,310 g CO2 per litre of petrol burned (UK E5/E10 average)
        static let petrolCO2GramsPerLiter: Double = 2310.0

        /// Instantaneous CO2 mass flow rate (grams per minute)
        let co2GramsPerMinute: Double
        /// Distance-normalized CO2 output (grams per km) when moving; nil when stationary
        let co2GramsPerKm: Double?
        /// 0 (very clean) ... 100 (heavy rich-burn / high emissions risk) estimated smoke & pollution index
        let smokeRiskScore: Int
        let cleanliness: ExhaustCleanliness
        let primaryFactor: String
    }

    /// Calculates exact stoichiometric CO2 emissions from fuel flow and estimates exhaust cleanliness / smoke risk
    /// from coolant warmup, fuel trims (rich/lean mixture), engine load enrichment, and active MIL/DTCs.
    /// Note: Petrol OBD-II ECUs do not have a physical tailpipe soot/PM sensor, so smoke risk is an ECU-derived estimate.
    static func estimateExhaustEmissions(
        fuelLitersPerHour: Double,
        speedKmh: Double,
        rpm: Double,
        coolantCelsius: Double?,
        engineLoadPercent: Double,
        stftPercent: Double?,
        ltftPercent: Double?,
        milOn: Bool
    ) -> EmissionsEstimate {
        let co2PerMin = (max(fuelLitersPerHour, 0) * EmissionsEstimate.petrolCO2GramsPerLiter) / 60.0
        let co2PerKm: Double?
        if speedKmh > 2.0 && fuelLitersPerHour > 0.02 {
            // (L/h * 2310 g/L) / (km/h) = g/km
            co2PerKm = min((fuelLitersPerHour * EmissionsEstimate.petrolCO2GramsPerLiter) / speedKmh, 999.0)
        } else {
            co2PerKm = nil
        }

        guard rpm > 200 else {
            return EmissionsEstimate(
                co2GramsPerMinute: 0,
                co2GramsPerKm: nil,
                smokeRiskScore: 0,
                cleanliness: .clean,
                primaryFactor: "Engine Off"
            )
        }

        var risk = 10.0
        var reasons: [String] = []

        // 1. Cold engine / catalyst not yet at light-off temp (high HC & CO)
        if let coolant = coolantCelsius, coolant < 65.0 {
            let coldPenalty = min(35.0, (65.0 - coolant) * 0.8)
            risk += coldPenalty
            reasons.append("Cold Catalyst")
        }

        // 2. Fuel trim deviations (negative trim = ECU pulling fuel because mixture is running rich)
        let combinedTrim = (stftPercent ?? 0.0) + (ltftPercent ?? 0.0)
        if combinedTrim < -10.0 {
            risk += min(35.0, abs(combinedTrim + 10.0) * 2.5 + 15.0)
            reasons.append("Rich Mixture")
        } else if combinedTrim > 12.0 {
            risk += min(25.0, (combinedTrim - 12.0) * 2.0 + 10.0)
            reasons.append("Lean / High NOx")
        }

        // 3. High load power enrichment (open-loop full-throttle produces unburnt hydrocarbons & CO)
        if engineLoadPercent > 78.0 {
            risk += min(25.0, (engineLoadPercent - 78.0) * 1.1)
            reasons.append("Heavy Load")
        }

        // 4. High CO2 intensity (>160 g/km for a small 800cc car)
        if let gPerKm = co2PerKm, gPerKm > 160.0 {
            risk += min(18.0, (gPerKm - 160.0) * 0.12)
        }

        // 5. Active Check Engine light (potential O2, catalyst, or misfire issue)
        if milOn {
            risk += 30.0
            reasons.append("Check Engine Active")
        }

        let clampedRisk = max(0, min(100, Int(risk.rounded())))
        let cleanliness: ExhaustCleanliness
        if clampedRisk >= 65 {
            cleanliness = .highRisk
        } else if let coolant = coolantCelsius, coolant < 65.0, clampedRisk >= 28 {
            cleanliness = .warmingUp
        } else if clampedRisk >= 35 {
            cleanliness = .elevated
        } else {
            cleanliness = .clean
        }

        let primaryFactor = reasons.first ?? "Optimal Stoichiometric Burn"
        return EmissionsEstimate(
            co2GramsPerMinute: co2PerMin,
            co2GramsPerKm: co2PerKm,
            smokeRiskScore: clampedRisk,
            cleanliness: cleanliness,
            primaryFactor: primaryFactor
        )
    }
}
