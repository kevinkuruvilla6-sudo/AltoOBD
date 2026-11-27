import SwiftUI
import Charts

struct TripsView: View {
    @EnvironmentObject private var coordinator: OBDCoordinator
    @EnvironmentObject private var tripStore: TripStore

    private var units: UnitSystem { coordinator.profile.unitSystem }
    private var trip: TripRecord { tripStore.currentTrip }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    currentTripCard
                    mileageChartCard
                    lifetimeSummaryCard
                    savedTripsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Mileage & Trips")
        }
    }

    private var currentTripCard: some View {
        let avgEcon = units.convertEconomy(kmPerLiter: trip.averageKmPerLiter)
        let dist = units.convertDistance(km: trip.distanceKm)
        let avgSpeed = units.convertSpeed(kmh: trip.averageSpeedKmh)
        let maxSpeed = units.convertSpeed(kmh: trip.maxSpeedKmh)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE TRIP COMPUTER")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .tracking(0.8)
                    Text("Started \(trip.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save & Reset") {
                    tripStore.saveAndResetTrip(profile: coordinator.profile)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.cyan.opacity(0.2), in: Capsule())
                .foregroundStyle(.cyan)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(avgEcon.map { String(format: "%.1f", $0) } ?? "--.-")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("Avg \(units.economyUnit)")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%@%.2f", trip.currencySymbol, trip.estimatedFuelCost))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("Est. Fuel Cost")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCell("Distance", String(format: "%.2f %@", dist, units.distanceUnit))
                statCell("Fuel Burned", String(format: "%.2f L", trip.fuelUsedLiters))
                statCell("Trip CO₂", String(format: "%.2f kg", trip.totalCO2Kg))
                statCell("Avg CO₂", trip.averageCO2GramsPerKm.map { String(format: "%.0f g/km", $0) } ?? "--")
                statCell("Avg Speed", String(format: "%.0f %@", avgSpeed, units.speedUnit))
                statCell("Idle Time", String(format: "%.0f%%", trip.idlePercentage))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var mileageChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LIVE ECONOMY TREND", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Spacer()
                Text(units.economyUnit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if tripStore.recentEconomyPoints.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Drive above 5 km/h (or start Demo Mode) to plot live mileage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
            } else {
                Chart(tripStore.recentEconomyPoints) { point in
                    if let val = units.convertEconomy(kmPerLiter: point.kmPerLiter) {
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value(units.economyUnit, val)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.mint.opacity(0.35), Color.mint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(units.economyUnit, val)
                        )
                        .foregroundStyle(.mint)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 150)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var lifetimeSummaryCard: some View {
        let totalDist = units.convertDistance(km: tripStore.lifetimeDistanceKm)
        let avgEcon = units.convertEconomy(kmPerLiter: tripStore.lifetimeAverageKmPerLiter)

        return HStack {
            statCell("Logged Dist", String(format: "%.1f %@", totalDist, units.distanceUnit))
            Spacer()
            statCell("Total Fuel", String(format: "%.2f L", tripStore.lifetimeFuelLiters))
            Spacer()
            statCell("Total CO₂", String(format: "%.1f kg", tripStore.lifetimeCO2Kg))
            Spacer()
            statCell("Overall Avg", avgEcon.map { String(format: "%.1f %@", $0, units.economyUnit) } ?? "--")
        }
        .padding(16)
        .background(cardBackground)
    }

    private var savedTripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVED TRIPS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            if tripStore.savedTrips.isEmpty {
                Text("No saved trips yet. Tap \"Save & Reset\" after a drive to build your Alto 800 mileage log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(cardBackground)
            } else {
                ForEach(tripStore.savedTrips) { item in
                    let econ = units.convertEconomy(kmPerLiter: item.averageKmPerLiter)
                    let dist = units.convertDistance(km: item.distanceKm)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(String(format: "%.1f %@ • %.2f L • Max %.0f %@",
                                        dist, units.distanceUnit, item.fuelUsedLiters,
                                        units.convertSpeed(kmh: item.maxSpeedKmh), units.speedUnit))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(econ.map { String(format: "%.1f %@", $0, units.economyUnit) } ?? "--")
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.mint)
                            Text(String(format: "%@%.2f", item.currencySymbol, item.estimatedFuelCost))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(cardBackground)
                }
            }
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatSeconds(_ secs: Double) -> String {
        let total = Int(secs)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(red: 0.09, green: 0.11, blue: 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}
