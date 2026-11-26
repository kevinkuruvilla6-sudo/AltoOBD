import SwiftUI

@main
struct AltoOBDDashboardApp: App {
    @StateObject private var coordinator = OBDCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.tripStore)
                .preferredColorScheme(.dark)
        }
    }
}
