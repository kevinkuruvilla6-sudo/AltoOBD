import Foundation
import Combine
import SwiftUI

/// A completed or active driving trip with integrated distance, fuel consumption, and engine extremes.
struct TripRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var startDate: Date
    var endDate: Date
    var distanceKm: Double
    var fuelUsedLiters: Double
    var idleSeconds: Double
    var movingSeconds: Double
    var maxSpeedKmh: Double
    var maxRPM: Double
    var maxCoolantCelsius: Double?
    var fuelPricePerLiter: Double
    var currencySymbol: String

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date = Date(),
        distanceKm: Double = 0,
        fuelUsedLiters: Double = 0,
        idleSeconds: Double = 0,
        movingSeconds: Double = 0,
        maxSpeedKmh: Double = 0,
        maxRPM: Double = 0,
        maxCoolantCelsius: Double? = nil,
        fuelPricePerLiter: Double = 1.45,
        currencySymbol: String = "£"
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceKm = distanceKm
        self.fuelUsedLiters = fuelUsedLiters
        self.idleSeconds = idleSeconds
        self.movingSeconds = movingSeconds
        self.maxSpeedKmh = maxSpeedKmh
        self.maxRPM = maxRPM
        self.maxCoolantCelsius = maxCoolantCelsius
        self.fuelPricePerLiter = fuelPricePerLiter
        self.currencySymbol = currencySymbol
    }

    var totalDurationSeconds: Double {
        idleSeconds + movingSeconds
    }

    var averageKmPerLiter: Double? {
        guard distanceKm > 0.05, fuelUsedLiters > 0.005 else { return nil }
        return distanceKm / fuelUsedLiters
    }

    var averageSpeedKmh: Double {
        let totalHours = totalDurationSeconds / 3600.0
        guard totalHours > 0.001 else { return 0 }
        return distanceKm / totalHours
    }

    var idlePercentage: Double {
        guard totalDurationSeconds > 1 else { return 0 }
        return (idleSeconds / totalDurationSeconds) * 100.0
    }

    var estimatedFuelCost: Double {
        fuelUsedLiters * fuelPricePerLiter
    }
}

/// Manages active trip integration and persists saved trips to local JSON storage.
@MainActor
final class TripStore: ObservableObject {
    @Published var currentTrip: TripRecord
    @Published private(set) var savedTrips: [TripRecord] = []
    @Published private(set) var recentEconomyPoints: [EconomyDataPoint] = []

    private var lastUpdateTimestamp: Date?
    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = docs.appendingPathComponent("alto_obd_trips.json")
        self.currentTrip = TripRecord()
        loadTrips()
    }

    func recordTelemetry(_ snapshot: TelemetrySnapshot, profile: VehicleProfile) {
        let now = snapshot.timestamp
        defer { lastUpdateTimestamp = now }

        currentTrip.fuelPricePerLiter = profile.fuelPricePerLiter
        currentTrip.currencySymbol = profile.currencySymbol

        guard let prev = lastUpdateTimestamp else { return }
        let dt = now.timeIntervalSince(prev)
        // Ignore stale gaps (> 5 seconds) to avoid huge distance jumps on reconnect
        guard dt > 0.02 && dt < 5.0 else { return }

        // Only accumulate when engine is running
        guard snapshot.rpm > 200 else { return }

        let hours = dt / 3600.0
        let deltaDistanceKm = snapshot.speedKmh * hours
        let deltaFuelLiters = snapshot.fuelFlowLitersPerHour * hours

        currentTrip.endDate = now
        currentTrip.distanceKm += deltaDistanceKm
        currentTrip.fuelUsedLiters += deltaFuelLiters

        if snapshot.speedKmh >= 2.0 {
            currentTrip.movingSeconds += dt
        } else {
            currentTrip.idleSeconds += dt
        }

        if snapshot.speedKmh > currentTrip.maxSpeedKmh {
            currentTrip.maxSpeedKmh = snapshot.speedKmh
        }
        if snapshot.rpm > currentTrip.maxRPM {
            currentTrip.maxRPM = snapshot.rpm
        }
        if let coolant = snapshot.coolantTempCelsius {
            currentTrip.maxCoolantCelsius = max(currentTrip.maxCoolantCelsius ?? coolant, coolant)
        }

        if let kpl = snapshot.smoothedKmPerLiter, snapshot.speedKmh >= 5.0 {
            recentEconomyPoints.append(EconomyDataPoint(timestamp: now, speedKmh: snapshot.speedKmh, kmPerLiter: kpl))
            if recentEconomyPoints.count > 90 {
                recentEconomyPoints.removeFirst(recentEconomyPoints.count - 90)
            }
        }
    }

    func saveAndResetTrip(profile: VehicleProfile) {
        if currentTrip.distanceKm >= 0.05 || currentTrip.totalDurationSeconds >= 10 {
            var completed = currentTrip
            completed.endDate = Date()
            savedTrips.insert(completed, at: 0)
            persistTrips()
        }
        resetCurrentTrip(profile: profile)
    }

    func resetCurrentTrip(profile: VehicleProfile) {
        currentTrip = TripRecord(
            fuelPricePerLiter: profile.fuelPricePerLiter,
            currencySymbol: profile.currencySymbol
        )
        recentEconomyPoints.removeAll()
        lastUpdateTimestamp = nil
    }

    func deleteTrips(at offsets: IndexSet) {
        savedTrips.remove(atOffsets: offsets)
        persistTrips()
    }

    var lifetimeDistanceKm: Double {
        savedTrips.reduce(0) { $0 + $1.distanceKm } + currentTrip.distanceKm
    }

    var lifetimeFuelLiters: Double {
        savedTrips.reduce(0) { $0 + $1.fuelUsedLiters } + currentTrip.fuelUsedLiters
    }

    var lifetimeAverageKmPerLiter: Double? {
        guard lifetimeDistanceKm > 0.1, lifetimeFuelLiters > 0.01 else { return nil }
        return lifetimeDistanceKm / lifetimeFuelLiters
    }

    private func loadTrips() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TripRecord].self, from: data) else {
            return
        }
        savedTrips = decoded
    }

    private func persistTrips() {
        guard let data = try? JSONEncoder().encode(savedTrips) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
