import SwiftUI
struct WatchDashboard: View {
    @EnvironmentObject private var monitor: WatchHeartMonitor
    var body: some View {
        VStack(spacing: 10) {
            Text("PULSE").font(.headline)
            Text(monitor.bpm.map { String(format: "%.0f BPM", $0) } ?? "-- BPM")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(monitor.status).font(.caption2).multilineTextAlignment(.center)
            Button(monitor.active ? "Stop" : "Start") {
                if monitor.active { monitor.stop() } else { monitor.start() }
            }
        }.padding()
    }
}
