import SwiftUI
@main
struct PulseWatchApp: App {
    @StateObject private var monitor = WatchHeartMonitor()
    var body: some Scene {
        WindowGroup { WatchDashboard().environmentObject(monitor) }
    }
}
