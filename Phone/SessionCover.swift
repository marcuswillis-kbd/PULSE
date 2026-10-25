import SwiftUI
import UIKit

struct SessionCover: View {
    @ObservedObject var engine: BreathEngine
    var bpm: Double?
    var personalBest: TimeInterval?
    var onStop: () -> Void
    var onDone: () -> Void

    var body: some View {
        Group {
            if let personalBest {
                PersonalBestMoment(time: personalBest, onDone: onDone)
            } else {
                MonotypeBreath(engine: engine, bpm: bpm) { ink in
                    Button("Stop", action: onStop)
                        .buttonStyle(.plain)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(ink)
                        .frame(minHeight: 44)
                }
                .onChange(of: engine.finishedNaturally) { _, finished in
                    if finished { onStop() }
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

struct PersonalBestMoment: View {
    var time: TimeInterval
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("New personal best")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .tracking(1)
                Text(DurationText.clock(time))
                    .font(.system(size: 88, weight: .light, design: .monospaced))
                    .minimumScaleFactor(0.4)
                Button("Done", action: onDone)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .padding(.top, 12)
            }
            .foregroundStyle(.white)
        }
    }
}

struct SafetySheet: View {
    var onUnderstand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before a long hold")
                .font(.system(.title2, design: .monospaced))
            Text("Never practise in or near water, while driving, or standing where fainting could hurt you. Stop if you feel dizzy.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button("I understand", action: onUnderstand)
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

struct HistoryList: View {
    @ObservedObject var records: BreathRecords

    var body: some View {
        Group {
            if records.history.isEmpty {
                Text("No sessions yet")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                List(records.history) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.label)
                            .font(.system(.body, design: .monospaced))
                        Text(rowDetail(log))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func rowDetail(_ log: SessionLog) -> String {
        let when = log.endedAt.formatted(date: .abbreviated, time: .shortened)
        if log.longestHold > 0 {
            return "\(when)  ·  hold \(DurationText.clock(log.longestHold))"
        }
        let length = log.endedAt.timeIntervalSince(log.startedAt)
        return "\(when)  ·  \(DurationText.clock(length))"
    }
}
