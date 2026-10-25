import SwiftUI

/// Black field, white circle. Inhale fills the screen, hold rests, exhale returns to black.
struct MonotypeBreath<Footer: View>: View {
    @ObservedObject var engine: BreathEngine
    var bpm: Double?
    var compact: Bool = false
    var footer: (Color) -> Footer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let maxDiameter = hypot(geo.size.width, geo.size.height) + 4
            timeline { date in
                let fraction = breathFraction(at: date)
                let diameter = circleDiameter(fraction: fraction, maxDiameter: maxDiameter, at: date)
                let ink: Color = fraction > 0.55 ? .black : .white
                ZStack {
                    Color.black
                    Circle()
                        .fill(Color.white)
                        .frame(width: diameter, height: diameter)
                    VStack(spacing: compact ? 4 : 12) {
                        if let bpm, bpm.isFinite, bpm > 0 {
                            Text(String(format: "%.0f BPM", bpm))
                                .font(.system(size: compact ? 12 : 16, weight: .regular, design: .monospaced))
                                .foregroundStyle(ink)
                        }
                        Spacer()
                        if engine.running {
                            Text(engine.phase.label)
                                .font(.system(size: compact ? 14 : 22, weight: .medium, design: .monospaced))
                                .tracking(compact ? 2 : 6)
                            Text(readout(at: date))
                                .font(.system(size: compact ? 40 : 92, weight: .light, design: .monospaced))
                                .minimumScaleFactor(0.4)
                                .monospacedDigit()
                        } else {
                            Text("PULSE")
                                .font(.system(size: compact ? 16 : 28, weight: .medium, design: .monospaced))
                                .tracking(4)
                        }
                        Spacer()
                        footer(ink)
                    }
                    .foregroundStyle(ink)
                    .padding(compact ? 8 : 24)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func timeline<Content: View>(@ViewBuilder _ content: @escaping (Date) -> Content) -> some View {
        if reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                content(context.date)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.running)) { context in
                content(context.date)
            }
        }
    }

    private func breathFraction(at date: Date) -> CGFloat {
        guard engine.running else { return 0 }
        if reduceMotion {
            switch engine.phase {
            case .inhale, .hold: return 1
            case .exhale: return 0
            }
        }
        let duration = max(engine.phaseDuration, 0.001)
        let raw = min(1, max(0, date.timeIntervalSince(engine.phaseStart) / duration))
        switch engine.phase {
        case .inhale: return raw
        case .hold: return 1
        case .exhale: return 1 - raw
        }
    }

    private func circleDiameter(fraction: CGFloat, maxDiameter: CGFloat, at date: Date) -> CGFloat {
        let minimum: CGFloat = compact ? 12 : 28
        let base = minimum + (maxDiameter - minimum) * fraction
        guard engine.running, engine.phase == .hold, !reduceMotion else { return base }
        return base * pulseScale(at: date)
    }

    /// Live heart rate sets the pulse period when a real reading is present.
    /// Otherwise the white field rests on a slow fixed rhythm. The period is never shown as BPM.
    private func pulseScale(at date: Date) -> CGFloat {
        let period: Double
        if let bpm, bpm.isFinite, bpm >= 35, bpm <= 220 {
            period = 60.0 / bpm
        } else {
            period = 4.5
        }
        let wave = sin(date.timeIntervalSinceReferenceDate / period * 2 * .pi)
        return 1 - 0.035 * CGFloat((wave + 1) / 2)
    }

    private func readout(at date: Date) -> String {
        let remaining = engine.phaseEnd.timeIntervalSince(date)
        return DurationText.countdown(remaining: remaining, phaseDuration: engine.phaseDuration)
    }
}
