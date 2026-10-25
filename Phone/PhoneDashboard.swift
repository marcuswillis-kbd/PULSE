import SwiftUI

struct PhoneDashboard: View {
    @EnvironmentObject private var receiver: WatchHeartReceiver
    @State private var inhale = 4.0
    @State private var hold = 0.0
    @State private var exhale = 6.0
    @State private var playing = false
    @State private var started = Date()
    private var cycle: Double { max(1, inhale + hold + exhale) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("PULSE").font(.largeTitle.bold())
                    Text("LIVE WATCH HEART RATE").font(.caption).foregroundStyle(.secondary)
                    Text(receiver.bpm.map { String(format: "%.0f BPM", $0) } ?? "-- BPM")
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(receiver.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .standard))" } ?? "Start a session on your Watch")
                        .font(.footnote).foregroundStyle(.secondary)
                    TimelineView(.animation(paused: !playing)) { context in
                        let t = playing ? context.date.timeIntervalSince(started).truncatingRemainder(dividingBy: cycle) : 0
                        let isInhale = t < inhale
                        let isHold = t < inhale + hold
                        let phase = isInhale ? "INHALE" : (isHold ? "HOLD" : "EXHALE")
                        let fraction = isInhale ? (t / max(inhale, 0.01)) : (isHold ? 1 : 1 - (t - inhale - hold) / max(exhale, 0.01))
                        ZStack {
                            Circle().fill(Color.cyan.opacity(0.15)).frame(width: 270, height: 270)
                            Circle().fill(Color.cyan.gradient).frame(width: 140 + 110 * fraction, height: 140 + 110 * fraction)
                            Text(phase).font(.headline).foregroundStyle(.black)
                        }.frame(height: 285)
                    }
                    timing("Inhale", $inhale, 2...8)
                    timing("Hold", $hold, 0...8)
                    timing("Exhale", $exhale, 2...12)
                    Button(playing ? "Stop guide" : "Start guide") { playing.toggle(); started = Date() }
                        .buttonStyle(.borderedProminent)
                    Text("Apple Watch BPM depends on connectivity. HRV is not a continuous stream.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
        }
    }
    private func timing(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue))s") }
            Slider(value: value, in: range, step: 1)
        }
    }
}
