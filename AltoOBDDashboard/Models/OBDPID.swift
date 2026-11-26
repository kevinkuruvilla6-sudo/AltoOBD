import Foundation

/// Standard OBD-II Mode 01 Parameter IDs (PIDs) relevant to a Suzuki Alto 800 / EOBD petrol ECU.
enum OBDPID: UInt8, CaseIterable, Identifiable {
    case supportedPIDs01to20 = 0x00
    case monitorStatus = 0x01
    case calculatedEngineLoad = 0x04
    case coolantTemperature = 0x05
    case shortTermFuelTrimB1 = 0x06
    case longTermFuelTrimB1 = 0x07
    case intakeManifoldPressure = 0x0B // MAP (kPa) - key for Suzuki F8D Speed-Density mileage
    case engineRPM = 0x0C
    case vehicleSpeed = 0x0D
    case timingAdvance = 0x0E
    case intakeAirTemperature = 0x0F   // IAT (°C) - key for Speed-Density mileage
    case mafAirFlowRate = 0x10         // MAF (g/s) - used if ECU supports it
    case throttlePosition = 0x11
    case runTimeSinceStart = 0x1F
    case supportedPIDs21to40 = 0x20
    case distanceWithMILOn = 0x21
    case fuelTankLevel = 0x2F
    case distanceSinceCodesCleared = 0x31
    case supportedPIDs41to60 = 0x40
    case controlModuleVoltage = 0x42

    var id: UInt8 { rawValue }

    /// Command string sent to the ELM327 adapter (e.g., "010C")
    var command: String {
        String(format: "01%02X", rawValue)
    }

    /// Expected number of data bytes returned after the `41 <PID>` header.
    var expectedByteCount: Int {
        switch self {
        case .supportedPIDs01to20, .supportedPIDs21to40, .supportedPIDs41to60, .monitorStatus:
            return 4
        case .engineRPM, .mafAirFlowRate, .runTimeSinceStart, .distanceWithMILOn, .distanceSinceCodesCleared, .controlModuleVoltage:
            return 2
        default:
            return 1
        }
    }

    var displayName: String {
        switch self {
        case .supportedPIDs01to20: return "Supported PIDs (01-20)"
        case .monitorStatus: return "MIL & Monitor Status"
        case .calculatedEngineLoad: return "Engine Load"
        case .coolantTemperature: return "Coolant Temp"
        case .shortTermFuelTrimB1: return "Short Term Fuel Trim"
        case .longTermFuelTrimB1: return "Long Term Fuel Trim"
        case .intakeManifoldPressure: return "Manifold Pressure (MAP)"
        case .engineRPM: return "Engine RPM"
        case .vehicleSpeed: return "Vehicle Speed"
        case .timingAdvance: return "Ignition Timing Advance"
        case .intakeAirTemperature: return "Intake Air Temp (IAT)"
        case .mafAirFlowRate: return "Mass Air Flow (MAF)"
        case .throttlePosition: return "Throttle Position"
        case .runTimeSinceStart: return "Engine Run Time"
        case .supportedPIDs21to40: return "Supported PIDs (21-40)"
        case .distanceWithMILOn: return "Distance w/ Check Engine"
        case .fuelTankLevel: return "Fuel Tank Level"
        case .distanceSinceCodesCleared: return "Distance Since Clear"
        case .supportedPIDs41to60: return "Supported PIDs (41-60)"
        case .controlModuleVoltage: return "ECU Voltage"
        }
    }

    var unit: String {
        switch self {
        case .calculatedEngineLoad, .shortTermFuelTrimB1, .longTermFuelTrimB1, .throttlePosition, .fuelTankLevel:
            return "%"
        case .coolantTemperature, .intakeAirTemperature:
            return "°C"
        case .intakeManifoldPressure:
            return "kPa"
        case .engineRPM:
            return "RPM"
        case .vehicleSpeed:
            return "km/h"
        case .timingAdvance:
            return "°"
        case .mafAirFlowRate:
            return "g/s"
        case .runTimeSinceStart:
            return "s"
        case .distanceWithMILOn, .distanceSinceCodesCleared:
            return "km"
        case .controlModuleVoltage:
            return "V"
        default:
            return ""
        }
    }
}
