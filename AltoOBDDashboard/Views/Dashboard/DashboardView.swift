import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var coordinator: OBDCoordinator
    @EnvironmentObject private var tripStore: TripStore

    var onOpenConnect: () -> Void
    var onOpenDiagnostics: () -> Void

    private var units: UnitSystem { coordinator.profile.unitSystem }
    private var snap: TelemetrySnapshot { coordinator.telemetry }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerStatusBar

                    // Active critical / warning banners (coolant overheat, battery, MIL)
                    let alerts = snap.activeAlerts(for: coordinator.profile)
                    if !alerts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(alerts) { alert in
                                alertBanner(alert)
                            }
                        }
                    }

                    // Quick start banner if not connected yet
                    if !coordinator.isLiveOrSimulated {
                        notConnectedCard
                    }

                    // Primary Dual Gauges (Speedometer + Tachometer)
                    HStack(spacing: 14) {
                        let displaySpeed = units.convertSpeed(kmh: snap.speedKmh)
                        CircularGaugeView(
                            title: "Speed",
                            value: displaySpeed,
                            formattedValue: "\(Int(displaySpeed.rounded()))",
                            unit: units.speedUnit,
                            minValue: 0,
                            maxValue: units.maxSpeedGauge,
                            accentColor: .cyan
                        )
                        .padding(8)
                        .background(cardBackground)

                        CircularGaugeView(
                            title: "Engine",
                            value: snap.rpm,
                            formattedValue: "\(Int(snap.rpm.rounded()))",
                            unit: "RPM",
                            minValue: 0,
                            maxValue: coordinator.profile.maxGaugeRPM,
                            warningThreshold: coordinator.profile.redlineRPM,
                            accentColor: .mint,
                            subtitle: snap.shiftAdvice
                        )
                        .padding(8)
                        .background(cardBackground)
                    }

                    // Prominent Mileage & Fuel Economy Card
                    mileageHeroCard

                    // Vital Engine & Electrical Health Grid
                    vitalsGridSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(coordinator.profile.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(coordinator.bleManager.detectedProtocolName == "Auto" && coordinator.isDemoMode
                             ? "796cc F8D • MAP Speed-Density"
                             : "\(String(format: "%.3fL", coordinator.profile.displacementLiters)) • \(coordinator.bleManager.detectedProtocolName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerStatusBar: some View {
        HStack {
            Button(action: onOpenConnect) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 9, height: 9)
                    Text(coordinator.connectionBadgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
            }

            Spacer()

            if coordinator.isLiveOrSimulated {
                Text(snap.fuelSource.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
                    .foregroundStyle(.cyan)
            } else {
                Button("Try Demo") {
                    coordinator.setDemoMode(true)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.cyan.opacity(0.2), in: Capsule())
                .foregroundStyle(.cyan)
            }
        }
    }

    private var notConnectedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "car.badge.gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Your Bluetooth OBD-II")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Plug into the Alto 800 OBD port under the steering column and turn ignition ON.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button(action: onOpenConnect) {
                    Label("Scan BLE Adapter", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                }
                Button {
                    coordinator.setDemoMode(true)
                } label: {
                    Label("Alto 800 Demo", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var mileageHeroCard: some View {
        let liveEcon = units.convertEconomy(kmPerLiter: snap.smoothedKmPerLiter)
        let tripEcon = units.convertEconomy(kmPerLiter: tripStore.currentTrip.averageKmPerLiter)
        let estRange = coordinator.estimatedRangeKm.map { units.convertDistance(km: $0) }

        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("LIVE MILEAGE", systemImage: "fuelpump.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .tracking(0.8)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(liveEcon.map { String(format: "%.1f", $0) } ?? "--.-")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(units.economyUnit)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("TRIP AVG")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(tripEcon.map { String(format: "%.1f %@", $0, units.economyUnit) } ?? "--")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.mint)

                    Text(String(format: "%.2f L/h burn", snap.fuelFlowLitersPerHour))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            // Eco Driving Score Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Eco Driving Score")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snap.ecoScore)/100")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(ecoColor(score: snap.ecoScore))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(ecoColor(score: snap.ecoScore))
                            .frame(width: geo.size.width * CGFloat(snap.ecoScore) / 100.0)
                            .animation(.easeOut(duration: 0.3), value: snap.ecoScore)
                    }
                }
                .frame(height: 8)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                miniStat(
                    title: "Trip Dist",
                    value: String(format: "%.2f %@", units.convertDistance(km: tripStore.currentTrip.distanceKm), units.distanceUnit)
                )
                Spacer()
                miniStat(
                    title: "Fuel Used",
                    value: String(format: "%.2f L", tripStore.currentTrip.fuelUsedLiters)
                )
                Spacer()
                miniStat(
                    title: "Est. Cost",
                    value: String(format: "%@%.2f", coordinator.profile.currencySymbol, tripStore.currentTrip.estimatedFuelCost)
                )
                Spacer()
                miniStat(
                    title: "Est. Range",
                    value: estRange.map { String(format: "%.0f %@", $0, units.distanceUnit) } ?? "--"
                )
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var vitalsGridSection: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

        return VStack(alignment: .leading, spacing: 10) {
            Text("ENGINE & ELECTRICAL VITALS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                // Coolant Temperature
                vitalTile(
                    icon: "thermometer.medium",
                    title: "Coolant Temp",
                    value: snap.coolantTempCelsius.map {
                        String(format: "%.0f%@", units.convertTemperature(celsius: $0), units.temperatureUnit)
                    } ?? "--",
                    subtitle: coolantStatusText(snap.coolantTempCelsius),
                    tint: coolantColor(snap.coolantTempCelsius)
                )

                // Battery / Alternator Voltage
                vitalTile(
                    icon: "bolt.car.fill",
                    title: "Battery / Alt",
                    value: snap.batteryVoltage.map { String(format: "%.2f V", $0) } ?? "--",
                    subtitle: batteryStatusText(snap.batteryVoltage),
                    tint: batteryColor(snap.batteryVoltage)
                )

                // Engine Load
                vitalTile(
                    icon: "gauge.with.needle",
                    title: "Engine Load",
                    value: String(format: "%.0f%%", snap.engineLoadPercent),
                    subtitle: snap.engineLoadPercent > 80 ? "High Demand" : "Normal",
                    tint: snap.engineLoadPercent > 80 ? .orange : .cyan
                )

                // Throttle Position
                vitalTile(
                    icon: "dial.high.fill",
                    title: "Throttle",
                    value: String(format: "%.0f%%", snap.throttlePositionPercent),
                    subtitle: snap.throttlePositionPercent < 15 ? "Idle / Coast" : "Active",
                    tint: .mint
                )

                // Intake Manifold Pressure (MAP)
                vitalTile(
                    icon: "wind",
                    title: "Manifold (MAP)",
                    value: snap.manifoldPressureKpa.map { String(format: "%.0f kPa", $0) } ?? "--",
                    subtitle: "Vacuum / Load",
                    tint: .indigo
                )

                // Intake Air Temperature (IAT)
                vitalTile(
                    icon: "aqi.medium",
                    title: "Intake Air",
                    value: snap.intakeAirTempCelsius.map {
                        String(format: "%.0f%@", units.convertTemperature(celsius: $0), units.temperatureUnit)
                    } ?? "--",
                    subtitle: "Air Density Sensor",
                    tint: .teal
                )

                // Fuel Trims (Mixture Health)
                let stftStr = snap.shortTermFuelTrimPercent.map { String(format: "%+.1f%%", $0) } ?? "--"
                let ltftStr = snap.longTermFuelTrimPercent.map { String(format: "%+.1f%%", $0) } ?? "--"
                vitalTile(
                    icon: "drop.halffull",
                    title: "Fuel Trim (S/L)",
                    value: "\(stftStr) / \(ltftStr)",
                    subtitle: fuelTrimStatus(ltft: snap.longTermFuelTrimPercent),
                    tint: abs(snap.longTermFuelTrimPercent ?? 0) > 10 ? .orange : .green
                )

                // Ignition Timing / Run Time
                vitalTile(
                    icon: "sparkle",
                    title: "Ignition Timing",
                    value: snap.timingAdvanceDegrees.map { String(format: "%.1f°", $0) } ?? "--",
                    subtitle: "Run \(formatDuration(snap.runTimeSeconds))",
                    tint: .purple
                )
            }
        }
    }

    private func alertBanner(_ alert: VehicleAlert) -> some View {
        let color: Color = alert.level == .critical ? .red : .orange
        return Button(action: onOpenDiagnostics) {
            HStack(spacing: 12) {
                Image(systemName: alert.systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(alert.message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
            .background(color.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.6), lineWidth: 1))
        }
    }

    private func vitalTile(icon: String, title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(cardBackground)
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(red: 0.09, green: 0.11, blue: 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }

    // MARK: - Formatting & Status Helpers

    private var statusDotColor: Color {
        if coordinator.isDemoMode { return .orange }
        switch coordinator.bleManager.state {
        case .connected: return .green
        case .connecting, .initializingELM, .scanning: return .yellow
        default: return .red
        }
    }

    private func ecoColor(score: Int) -> Color {
        if score >= 75 { return .green }
        if score >= 45 { return .yellow }
        return .orange
    }

    private func coolantColor(_ tempC: Double?) -> Color {
        guard let t = tempC else { return .secondary }
        if t < 60 { return .blue }
        if t >= coordinator.profile.coolantWarningCelsius { return .red }
        if t >= 96 { return .orange }
        return .green
    }

    private func coolantStatusText(_ tempC: Double?) -> String {
        guard let t = tempC else { return "Waiting…" }
        if t < 60 { return "Cold Engine" }
        if t >= coordinator.profile.coolantWarningCelsius { return "OVERHEATING" }
        if t >= 96 { return "Warm / Fan On" }
        return "Optimal"
    }

    private func batteryColor(_ volts: Double?) -> Color {
        guard let v = volts else { return .secondary }
        if v < 11.8 || v > 15.0 { return .red }
        if v < 13.0 { return .orange }
        return .green
    }

    private func batteryStatusText(_ volts: Double?) -> String {
        guard let v = volts else { return "Waiting…" }
        if v > 15.0 { return "Overcharging" }
        if v >= 13.5 { return "Alternator OK" }
        if v >= 12.2 { return "Battery (Key On)" }
        return "Low Voltage"
    }

    private func fuelTrimStatus(ltft: Double?) -> String {
        guard let v = ltft else { return "Closed Loop" }
        if abs(v) <= 5 { return "Mixture Optimal" }
        if v > 10 { return "Running Lean" }
        if v < -10 { return "Running Rich" }
        return "Slight Trim"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%dm %02ds", m, s)
    }
}
