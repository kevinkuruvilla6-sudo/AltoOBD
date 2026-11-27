import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: OBDCoordinator
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onOpenConnect: { selectedTab = 3 }, onOpenDiagnostics: { selectedTab = 2 })
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

            TripsView()
                .tabItem {
                    Label("Mileage", systemImage: "fuelpump.fill")
                }
                .tag(1)

            DiagnosticsView()
                .tabItem {
                    Label("Diagnostics", systemImage: "wrench.and.screwdriver.fill")
                }
                .badge((coordinator.telemetry.milOn || !coordinator.storedDTCs.isEmpty) ? "!" : (nil as String?))
                .tag(2)

            ConnectionView()
                .tabItem {
                    Label("Connect", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(3)
        }
        .tint(Color.cyan)
    }
}
