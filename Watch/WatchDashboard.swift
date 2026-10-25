import SwiftUI

struct WatchDashboard: View {
    @EnvironmentObject private var monitor: WatchHeartMonitor

    var body: some View {
        MonotypeBreath(engine: monitor.guide, bpm: monitor.bpm, compact: true) { ink in
            VStack(spacing: 4) {
                Button(monitor.guide.running ? "Stop" : "Start") {
                    if monitor.guide.running {
                        monitor.userStop()
                    } else {
                        monitor.userStart()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(ink)
                if !monitor.guide.running {
                    Text(monitor.status)
                        .font(.system(size: 10, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ink)
                }
            }
        }
    }
}
