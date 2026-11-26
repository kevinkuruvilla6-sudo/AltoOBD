import Foundation

enum DTCSeverity: String, Codable {
    case low = "Info"
    case medium = "Warning"
    case high = "Critical"
}

enum DTCStatus: String, Codable {
    case stored = "Stored"
    case pending = "Pending"
}

/// Represents a decoded OBD-II Diagnostic Trouble Code (e.g., P0300, P0171).
struct DiagnosticCode: Identifiable, Hashable, Codable {
    var id: String { "\(status.rawValue)-\(code)" }
    let code: String
    let status: DTCStatus
    let title: String
    let guidance: String
    let severity: DTCSeverity

    init(code: String, status: DTCStatus = .stored) {
        let normalized = code.uppercased()
        self.code = normalized
        self.status = status
        let info = DTCDatabase.lookup(code: normalized)
        self.title = info.title
        self.guidance = info.guidance
        self.severity = info.severity
    }
}

/// Offline lookup dictionary for common EOBD / Suzuki Alto 800 & K10B petrol fault codes.
enum DTCDatabase {
    struct Entry {
        let title: String
        let guidance: String
        let severity: DTCSeverity
    }

    static let entries: [String: Entry] = [
        // Fuel & Air Metering (Common on Suzuki Alto MAP/IAT/O2 engines)
        "P0105": Entry(title: "MAP Sensor Circuit Malfunction", guidance: "Check vacuum hose to the intake manifold and MAP sensor connector.", severity: .medium),
        "P0106": Entry(title: "MAP Sensor Range/Performance", guidance: "Inspect MAP sensor vacuum line for leaks or blockage.", severity: .medium),
        "P0107": Entry(title: "MAP Sensor Circuit Low Input", guidance: "Possible short to ground or failed MAP sensor.", severity: .medium),
        "P0108": Entry(title: "MAP Sensor Circuit High Input", guidance: "Check MAP sensor wiring and manifold vacuum leaks.", severity: .medium),
        "P0112": Entry(title: "Intake Air Temp (IAT) Sensor Low", guidance: "Check IAT sensor connector near air filter box.", severity: .low),
        "P0113": Entry(title: "Intake Air Temp (IAT) Sensor High", guidance: "Open circuit or unplugged IAT sensor on intake duct.", severity: .low),
        "P0115": Entry(title: "Engine Coolant Temp Sensor Circuit", guidance: "Check ECT sensor connector on thermostat housing; fan may run constantly.", severity: .high),
        "P0117": Entry(title: "Engine Coolant Temp Sensor Low", guidance: "Sensor reading abnormally hot or shorted to ground. Check coolant level.", severity: .high),
        "P0118": Entry(title: "Engine Coolant Temp Sensor High", guidance: "Open circuit in coolant temp sensor; may cause poor cold starts.", severity: .medium),
        "P0120": Entry(title: "Throttle Position Sensor (TPS) Circuit", guidance: "Check TPS connector on throttle body; clean throttle plate.", severity: .medium),
        "P0122": Entry(title: "Throttle Position Sensor Low Input", guidance: "Inspect TPS wiring harness and sensor calibration.", severity: .medium),
        "P0123": Entry(title: "Throttle Position Sensor High Input", guidance: "Possible open ground on TPS or faulty sensor.", severity: .medium),
        "P0128": Entry(title: "Coolant Thermostat Below Regulating Temp", guidance: "Thermostat may be stuck open, reducing fuel economy and cabin heat.", severity: .low),
        "P0130": Entry(title: "O2 Sensor Circuit (Bank 1 Sensor 1)", guidance: "Inspect upstream lambda sensor wiring and exhaust manifold leaks.", severity: .medium),
        "P0131": Entry(title: "O2 Sensor Low Voltage (Bank 1 Sensor 1)", guidance: "Lean mixture or failing upstream oxygen sensor.", severity: .medium),
        "P0133": Entry(title: "O2 Sensor Slow Response (Bank 1 Sensor 1)", guidance: "Aging upstream lambda sensor; hurts fuel economy.", severity: .low),
        "P0134": Entry(title: "O2 Sensor No Activity (Bank 1 Sensor 1)", guidance: "Check lambda sensor plug and heater fuse.", severity: .medium),
        "P0135": Entry(title: "O2 Sensor Heater Circuit (Bank 1 Sensor 1)", guidance: "Check O2 heater fuse and resistance across heater pins.", severity: .low),
        "P0136": Entry(title: "O2 Sensor Circuit (Bank 1 Sensor 2)", guidance: "Downstream post-cat lambda sensor signal fault.", severity: .low),
        "P0141": Entry(title: "O2 Sensor Heater Circuit (Bank 1 Sensor 2)", guidance: "Post-cat O2 sensor heater failure; does not usually affect drivability.", severity: .low),
        "P0171": Entry(title: "System Too Lean (Bank 1)", guidance: "Look for vacuum leaks, weak fuel pump/filter, or dirty injectors.", severity: .medium),
        "P0172": Entry(title: "System Too Rich (Bank 1)", guidance: "Check air filter, leaking fuel injector, or faulty O2/MAP sensor.", severity: .medium),

        // Ignition & Misfire (3-cylinder Alto: cylinders 1, 2, 3)
        "P0300": Entry(title: "Random/Multiple Cylinder Misfire", guidance: "Check spark plugs, ignition coils, HT leads, and fuel pressure. Avoid hard driving.", severity: .high),
        "P0301": Entry(title: "Cylinder 1 Misfire Detected", guidance: "Inspect Cylinder 1 spark plug, ignition coil/lead, and injector.", severity: .high),
        "P0302": Entry(title: "Cylinder 2 Misfire Detected", guidance: "Inspect Cylinder 2 spark plug, ignition coil/lead, and injector.", severity: .high),
        "P0303": Entry(title: "Cylinder 3 Misfire Detected", guidance: "Inspect Cylinder 3 spark plug, ignition coil/lead, and injector.", severity: .high),
        "P0325": Entry(title: "Knock Sensor Circuit Malfunction", guidance: "Check knock sensor bolt torque and wiring on engine block.", severity: .medium),
        "P0335": Entry(title: "Crankshaft Position Sensor Circuit", guidance: "May cause stalling or no-start; inspect CKP sensor and wiring.", severity: .high),
        "P0340": Entry(title: "Camshaft Position Sensor Circuit", guidance: "Check CMP sensor connector and timing belt/chain alignment.", severity: .high),

        // Emissions, Idle & Speed
        "P0401": Entry(title: "EGR Flow Insufficient", guidance: "Carbon buildup in EGR valve or passages.", severity: .low),
        "P0420": Entry(title: "Catalyst System Efficiency Below Threshold", guidance: "Catalytic converter aging or exhaust leak near lambda sensors (MOT emission risk).", severity: .medium),
        "P0443": Entry(title: "EVAP Purge Control Valve Circuit", guidance: "Inspect canister purge solenoid connector and vacuum lines.", severity: .low),
        "P0500": Entry(title: "Vehicle Speed Sensor (VSS) Malfunction", guidance: "Check gearbox speed sensor connector; affects speedometer and mileage calc.", severity: .medium),
        "P0505": Entry(title: "Idle Air Control (IAC) System", guidance: "Clean idle air control valve and throttle body passages.", severity: .low),
        "P0560": Entry(title: "System Voltage Malfunction", guidance: "Test 12V battery and alternator charging output (should be 13.8-14.4V running).", severity: .medium),
        "P0562": Entry(title: "System Voltage Low", guidance: "Weak 12V battery, corroded terminals, or failing alternator.", severity: .high),
        "P0563": Entry(title: "System Voltage High", guidance: "Alternator voltage regulator overcharging (>15V). Service promptly.", severity: .high),
        "P0606": Entry(title: "ECU / PCM Processor Fault", guidance: "Check battery voltage and ECU ground straps.", severity: .high),

        // Common Suzuki manufacturer-specific codes
        "P1510": Entry(title: "Suzuki ECU Backup Power Supply", guidance: "Check battery terminals and main ECU backup fuse.", severity: .medium),
        "P1614": Entry(title: "Suzuki Immobilizer / Key Transponder", guidance: "Try spare key; inspect ignition antenna ring if car fails to start.", severity: .medium)
    ]

    static func lookup(code: String) -> Entry {
        if let match = entries[code] {
            return match
        }
        let systemDesc: String
        switch code.first {
        case "P": systemDesc = "Powertrain Fault"
        case "C": systemDesc = "Chassis Fault"
        case "B": systemDesc = "Body System Fault"
        case "U": systemDesc = "Network / Communication Fault"
        default: systemDesc = "Diagnostic Trouble Code"
        }
        return Entry(
            title: "\(systemDesc) (\(code))",
            guidance: "Search Suzuki EOBD code \(code) or have a mechanic inspect the freeze-frame data.",
            severity: .medium
        )
    }
}
