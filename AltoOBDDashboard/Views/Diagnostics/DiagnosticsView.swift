import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var coordinator: OBDCoordinator
    @State private var showClearConfirm = false
    @State private var commandInput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    milStatusCard
                    dtcResultsCard
                    supportedPIDsCard
                    terminalCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Diagnostics")
            .alert("Clear Check Engine Codes?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear Codes (Mode 04)", role: .destructive) {
                    Task { await coordinator.clearDiagnosticCodes() }
                }
            } message: {
                Text("This resets stored fault codes, Check Engine Light (MIL), and emissions readiness monitors (important before a UK MOT test). Only clear after noting the codes.")
            }
        }
    }

    private var milStatusCard: some View {
        let milOn = coordinator.telemetry.milOn || !coordinator.storedDTCs.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: milOn ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(milOn ? .orange : .green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(milOn ? "Check Engine Light Active" : "Engine ECU Status: Healthy")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(coordinator.lastDiagnosticMessage ?? "Tap Scan ECU to read stored (Mode 03) and pending (Mode 07) fault codes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await coordinator.scanDiagnosticCodes() }
                } label: {
                    HStack {
                        if coordinator.isScanningDTCs {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Scan ECU Faults")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black)
                }
                .disabled(coordinator.isScanningDTCs)

                Button {
                    showClearConfirm = true
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.red)
                }
                .disabled(!coordinator.isLiveOrSimulated)
            }

            if coordinator.isDemoMode {
                Button("Toggle Demo Check-Engine Fault (P0171)") {
                    coordinator.toggleSimulatedFault()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var dtcResultsCard: some View {
        let allCodes = coordinator.storedDTCs + coordinator.pendingDTCs
        return VStack(alignment: .leading, spacing: 10) {
            Text("FAULT CODES (\(allCodes.count))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            if allCodes.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("No stored or pending DTCs currently loaded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(allCodes) { dtc in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(dtc.code)
                                .font(.headline.monospaced().weight(.bold))
                                .foregroundStyle(.white)
                            Text(dtc.status.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(dtc.status == .stored ? Color.red.opacity(0.25) : Color.orange.opacity(0.25), in: Capsule())
                                .foregroundStyle(dtc.status == .stored ? .red : .orange)
                            Spacer()
                            Text(dtc.severity.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(dtc.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(dtc.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private var supportedPIDsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DETECTED ECU SENSORS (PIDS)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                Text("\(coordinator.supportedPIDs.count) active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
            }

            if coordinator.supportedPIDs.isEmpty {
                Text("Connect to your Suzuki Alto 800 to auto-detect supported OBD-II sensors (MAP, IAT, RPM, Speed, O2, Fuel Trims).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let known = OBDPID.allCases.filter { coordinator.supportedPIDs.contains($0.rawValue) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(known) { pid in
                        HStack(spacing: 6) {
                            Text(pid.command)
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(.cyan)
                            Text(pid.displayName)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var terminalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ELM327 AT COMMAND TERMINAL")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(coordinator.terminalOutput.suffix(18).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.hasPrefix(">") ? .cyan : (line.hasPrefix("!") ? .red : .green))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .frame(height: 130)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                TextField("e.g. ATI, ATRV, ATDP, 010C", text: $commandInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                Button("Send") {
                    let cmd = commandInput
                    commandInput = ""
                    Task { await coordinator.sendTerminalCommand(cmd) }
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(cardBackground)
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
