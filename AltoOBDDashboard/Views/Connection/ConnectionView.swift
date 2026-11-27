import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var coordinator: OBDCoordinator

    var body: some View {
        NavigationStack {
            List {
                // Bluetooth BLE Scanner Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connection Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(coordinator.connectionBadgeText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        if coordinator.bleManager.state.isConnected {
                            Button("Disconnect", role: .destructive) {
                                coordinator.bleManager.disconnect()
                            }
                            .buttonStyle(.bordered)
                        } else if case .scanning = coordinator.bleManager.state {
                            Button("Stop") {
                                coordinator.bleManager.stopScanning()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Scan BLE") {
                                coordinator.setDemoMode(false)
                                coordinator.bleManager.startScanning()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .foregroundStyle(.black)
                        }
                    }

                    if !coordinator.bleManager.state.isConnected {
                        Button {
                            coordinator.setDemoMode(false)
                            coordinator.bleManager.reconnectLastDevice()
                        } label: {
                            Label("Reconnect Last Adapter", systemImage: "arrow.clockwise")
                        }
                    }

                    Picker("ECU Protocol", selection: Binding(
                        get: { coordinator.bleManager.preferredProtocol },
                        set: { coordinator.bleManager.preferredProtocol = $0 }
                    )) {
                        ForEach(ELMProtocolOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Toggle("Show Unnamed BLE Devices", isOn: Binding(
                        get: { coordinator.bleManager.showAllBLEDevices },
                        set: { coordinator.bleManager.showAllBLEDevices = $0 }
                    ))

                    ForEach(coordinator.bleManager.discoveredDevices) { device in
                        Button {
                            coordinator.setDemoMode(false)
                            coordinator.bleManager.connect(to: device)
                        } label: {
                            HStack {
                                Image(systemName: device.isLikelyOBD ? "antenna.radiowaves.left.and.right" : "cpu")
                                    .foregroundStyle(device.isLikelyOBD ? .mint : .cyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(device.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        if device.isLikelyOBD {
                                            Text("OBD")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.mint.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.mint)
                                        }
                                    }
                                    Text("Signal: \(device.rssi) dBm")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Connect")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }

                    if !coordinator.bleManager.commandLog.isEmpty {
                        DisclosureGroup("ELM327 Connection Log") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(coordinator.bleManager.commandLog.suffix(12).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(line.hasPrefix("!") ? .red : (line.hasPrefix(">") ? .cyan : .secondary))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Bluetooth LE ELM327 Adapter")
                } footer: {
                    Text("Do NOT pair in iPhone Settings — connect directly here via Scan BLE. Supports ELM327 BLE 4.0/5.0 dongles (FFF0/FFE0/18F0/Nordic/ISSC). Note: Older Bluetooth Classic 2.0/3.0 blue ELM327 dongles are blocked by iOS hardware restrictions.")
                }

                // Live Simulator Toggle
                Section {
                    Toggle(isOn: Binding(
                        get: { coordinator.isDemoMode },
                        set: { coordinator.setDemoMode($0) }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Suzuki Alto 800 Demo Mode")
                                Text("Simulates UK town & A-road driving with live MAP Speed-Density MPG.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Testing & Preview")
                }

                // Vehicle Presets & Engine Calibration
                Section {
                    Menu {
                        ForEach(VehicleProfile.presets, id: \.name) { preset in
                            Button(preset.name) {
                                var updated = preset
                                updated.unitSystem = coordinator.profile.unitSystem
                                updated.fuelPricePerLiter = coordinator.profile.fuelPricePerLiter
                                coordinator.profile = updated
                            }
                        }
                    } label: {
                        HStack {
                            Text("Vehicle Preset")
                            Spacer()
                            Text(coordinator.profile.name)
                                .foregroundStyle(.cyan)
                        }
                    }

                    Picker("Units", selection: $coordinator.profile.unitSystem) {
                        ForEach(UnitSystem.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Engine Displacement")
                            Spacer()
                            Text(String(format: "%.3f L (%d cc)", coordinator.profile.displacementLiters, Int(coordinator.profile.displacementLiters * 1000)))
                                .monospacedDigit()
                                .foregroundStyle(.cyan)
                        }
                        Slider(value: $coordinator.profile.displacementLiters, in: 0.65...2.0, step: 0.002)
                            .tint(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Volumetric Efficiency (MPG Calibration)")
                            Spacer()
                            Text("\(Int((coordinator.profile.volumetricEfficiency * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.mint)
                        }
                        Slider(value: $coordinator.profile.volumetricEfficiency, in: 0.65...0.98, step: 0.01)
                            .tint(.mint)
                    }

                    Stepper(value: $coordinator.profile.fuelTankLiters, in: 20...65, step: 1) {
                        HStack {
                            Text("Fuel Tank Capacity")
                            Spacer()
                            Text("\(Int(coordinator.profile.fuelTankLiters)) L")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $coordinator.profile.fuelPricePerLiter, in: 0.50...3.00, step: 0.02) {
                        HStack {
                            Text("Petrol Price")
                            Spacer()
                            Text(String(format: "%@%.2f / L", coordinator.profile.currencySymbol, coordinator.profile.fuelPricePerLiter))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Alto 800 Cruz Calibration")
                } footer: {
                    Text("Because the 796cc Suzuki Alto 800 uses a MAP sensor instead of a MAF sensor, adjust Volumetric Efficiency (default 82%) slightly up or down after a full-tank fill-up to match pump-measured MPG within 1–2%.")
                }

                // Cockpit Preferences
                Section("Cockpit & Safety") {
                    Toggle("Keep Screen Awake While Driving", isOn: $coordinator.profile.keepScreenAwake)

                    Stepper(value: $coordinator.profile.coolantWarningCelsius, in: 92...112, step: 1) {
                        HStack {
                            Text("Coolant Overheat Alert")
                            Spacer()
                            Text("\(Int(coordinator.profile.coolantWarningCelsius))°C")
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Connect & Setup")
        }
    }
}
