import Foundation

/// Unit systems supported by the dashboard. UK Imperial (mph + UK MPG) is the default for UK-spec Alto drivers.
enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case ukImperial = "UK (mph / UK MPG)"
    case metricKmPerL = "Metric (km/h / km/L)"
    case metricLPer100 = "Metric (km/h / L/100km)"
    case usImperial = "US (mph / US MPG)"

    var id: String { rawValue }

    var speedUnit: String {
        switch self {
        case .ukImperial, .usImperial: return "mph"
        case .metricKmPerL, .metricLPer100: return "km/h"
        }
    }

    var distanceUnit: String {
        switch self {
        case .ukImperial, .usImperial: return "mi"
        case .metricKmPerL, .metricLPer100: return "km"
        }
    }

    var economyUnit: String {
        switch self {
        case .ukImperial: return "MPG"
        case .usImperial: return "MPG"
        case .metricKmPerL: return "km/L"
        case .metricLPer100: return "L/100km"
        }
    }

    var temperatureUnit: String {
        switch self {
        case .usImperial: return "°F"
        case .ukImperial, .metricKmPerL, .metricLPer100: return "°C"
        }
    }

    func convertSpeed(kmh: Double) -> Double {
        switch self {
        case .ukImperial, .usImperial:
            return kmh * 0.621371
        case .metricKmPerL, .metricLPer100:
            return kmh
        }
    }

    func convertDistance(km: Double) -> Double {
        switch self {
        case .ukImperial, .usImperial:
            return km * 0.621371
        case .metricKmPerL, .metricLPer100:
            return km
        }
    }

    func convertTemperature(celsius: Double) -> Double {
        switch self {
        case .usImperial:
            return (celsius * 9.0 / 5.0) + 32.0
        case .ukImperial, .metricKmPerL, .metricLPer100:
            return celsius
        }
    }

    /// Converts fuel economy from km/L into the currently selected unit.
    /// Returns nil when invalid (e.g. stationary or zero fuel flow).
    func convertEconomy(kmPerLiter: Double?) -> Double? {
        guard let kpl = kmPerLiter, kpl.isFinite, kpl > 0.1 else { return nil }
        switch self {
        case .ukImperial:
            // 1 UK Imperial gallon = 4.54609 L; 1 mile = 1.609344 km -> factor = 2.82481
            return min(kpl * 2.824809363, 199.9)
        case .usImperial:
            // 1 US gallon = 3.785411784 L; 1 mile = 1.609344 km -> factor = 2.352145
            return min(kpl * 2.352145833, 199.9)
        case .metricKmPerL:
            return min(kpl, 99.9)
        case .metricLPer100:
            return min(100.0 / kpl, 99.9)
        }
    }

    var maxSpeedGauge: Double {
        switch self {
        case .ukImperial, .usImperial: return 100
        case .metricKmPerL, .metricLPer100: return 160
        }
    }
}

/// Engine & vehicle calibration profile. Defaults to Suzuki Alto 800 Cruz (F8D 796cc 3-cyl petrol).
struct VehicleProfile: Codable, Equatable {
    var name: String
    /// Engine displacement in liters (0.796 L for F8D Alto 800, 0.998 L for K10B UK Alto 1.0)
    var displacementLiters: Double
    /// Estimated volumetric efficiency (0.70 - 0.95). Used for MAP Speed-Density fuel calculations.
    var volumetricEfficiency: Double
    /// Fuel tank capacity in liters (35 L standard on Suzuki Alto)
    var fuelTankLiters: Double
    /// Redline RPM for tachometer gauge
    var redlineRPM: Double
    /// Max RPM on tachometer scale
    var maxGaugeRPM: Double
    /// Coolant overheat threshold in Celsius
    var coolantWarningCelsius: Double
    /// Fuel price per liter in local currency (GBP default for UK)
    var fuelPricePerLiter: Double
    var currencySymbol: String
    var unitSystem: UnitSystem
    var keepScreenAwake: Bool

    static let alto800CruzUK = VehicleProfile(
        name: "Suzuki Alto 800 Cruz (UK)",
        displacementLiters: 0.796,
        volumetricEfficiency: 0.82,
        fuelTankLiters: 35.0,
        redlineRPM: 6000,
        maxGaugeRPM: 7000,
        coolantWarningCelsius: 102.0,
        fuelPricePerLiter: 1.45,
        currencySymbol: "£",
        unitSystem: .ukImperial,
        keepScreenAwake: true
    )

    static let alto1000UK = VehicleProfile(
        name: "Suzuki Alto 1.0 K10B (UK)",
        displacementLiters: 0.998,
        volumetricEfficiency: 0.85,
        fuelTankLiters: 35.0,
        redlineRPM: 6200,
        maxGaugeRPM: 7000,
        coolantWarningCelsius: 102.0,
        fuelPricePerLiter: 1.45,
        currencySymbol: "£",
        unitSystem: .ukImperial,
        keepScreenAwake: true
    )

    static let presets: [VehicleProfile] = [.alto800CruzUK, .alto1000UK]
}
