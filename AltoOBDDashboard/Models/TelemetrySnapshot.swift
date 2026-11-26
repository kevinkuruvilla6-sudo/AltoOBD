import Foundation

enum VehicleAlertLevel: String, Codable {
    case warning
    case critical
}

struct VehicleAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let level: VehicleAlertLevel
    let systemImage: String
}

/// A single historical economy sample for the live mileage trend chart.
struct EconomyDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let speedKmh: Double
    let kmPerLiter: Double
}

/// Complete live telemetry state from the Suzuki Alto 800 ECU (or Simulator).
struct TelemetrySnapshot {
    var timestamp: Date = Date()

    // Primary gauges
    var rpm: Double = 0
    var speedKmh: Double = 0
    var engineLoadPercent: Double = 0
    var throttlePositionPercent: Double = 0

    // Thermal & electrical health
    var coolantTempCelsius: Double? = nil
    var intakeAirTempCelsius: Double? = nil
    var batteryVoltage: Double? = nil

    // Air, fuel & ignition
    var manifoldPressureKpa: Double? = nil   // MAP
    var mafGramsPerSec: Double? = nil        // MAF (if ECU supports it)
    var shortTermFuelTrimPercent: Double? = nil
    var longTermFuelTrimPercent: Double? = nil
    var timingAdvanceDegrees: Double? = nil
    var fuelTankLevelPercent: Double? = nil  // Optional (not all Alto ECUs expose PID 2F)

    // Counters & Diagnostics
    var runTimeSeconds: Int = 0
    var distanceSinceCodesClearedKm: Double? = nil
    var milOn: Bool = false
    var dtcCount: Int = 0

    // Derived mileage metrics
    var fuelFlowLitersPerHour: Double = 0
    var instantKmPerLiter: Double? = nil
    var smoothedKmPerLiter: Double? = nil
    var fuelSource: ELM327Parser.FuelCalcSource = .unavailable

    /// 0...100 driving efficiency score based on RPM, throttle, load, and economy.
    var ecoScore: Int {
        guard rpm > 200 else { return 100 }
        if speedKmh < 2 { return 65 } // idling penalty
        var score = 100.0
        if rpm > 3500 { score -= min(35, (rpm - 3500) / 60.0) }
        if throttlePositionPercent > 55 { score -= min(25, (throttlePositionPercent - 55) * 0.6) }
        if engineLoadPercent > 75 { score -= min(20, (engineLoadPercent - 75) * 0.8) }
        if let kpl = smoothedKmPerLiter, kpl > 18.0 { score += 5 }
        return max(0, min(100, Int(score.rounded())))
    }

    /// Suggested gear-shift indicator for the 5-speed Suzuki Alto 800 gearbox.
    var shiftAdvice: String? {
        guard speedKmh > 8 else { return nil }
        if rpm > 3600 && throttlePositionPercent < 65 {
            return "SHIFT UP"
        } else if rpm < 1250 && engineLoadPercent > 70 {
            return "SHIFT DOWN"
        }
        return nil
    }

    /// Computes active safety/health alerts (coolant overheat, low/high voltage, check engine).
    func activeAlerts(for profile: VehicleProfile) -> [VehicleAlert] {
        var alerts: [VehicleAlert] = []

        if let coolant = coolantTempCelsius {
            if coolant >= profile.coolantWarningCelsius {
                alerts.append(VehicleAlert(
                    id: "coolant-hot",
                    title: "High Coolant Temp (\(Int(coolant))°C)",
                    message: "Engine is running hot. Pull over safely and check coolant level and radiator fan.",
                    level: .critical,
                    systemImage: "thermometer.high"
                ))
            }
        }

        if let volts = batteryVoltage {
            if volts < 11.8 {
                alerts.append(VehicleAlert(
                    id: "battery-low",
                    title: String(format: "Low Battery (%.1fV)", volts),
                    message: "Battery voltage is low. Check alternator belt or battery health.",
                    level: .critical,
                    systemImage: "battery.25"
                ))
            } else if rpm > 900 && volts < 13.0 {
                alerts.append(VehicleAlert(
                    id: "alternator-weak",
                    title: String(format: "Weak Charging (%.1fV)", volts),
                    message: "Expected 13.8–14.4V while engine is running. Alternator may be undercharging.",
                    level: .warning,
                    systemImage: "bolt.trianglebadge.exclamationmark"
                ))
            } else if volts > 15.0 {
                alerts.append(VehicleAlert(
                    id: "battery-high",
                    title: String(format: "Overcharging (%.1fV)", volts),
                    message: "Alternator regulator voltage is too high (>15.0V).",
                    level: .critical,
                    systemImage: "bolt.fill"
                ))
            }
        }

        if milOn || dtcCount > 0 {
            alerts.append(VehicleAlert(
                id: "mil-on",
                title: "Check Engine Light Active",
                message: "\(max(dtcCount, 1)) fault code(s) reported by ECU. Open Diagnostics tab to scan.",
                level: .warning,
                systemImage: "exclamationmark.triangle.fill"
            ))
        }

        return alerts
    }
}
