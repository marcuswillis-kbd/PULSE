import SwiftUI

struct PhoneDashboard: View {
    @EnvironmentObject private var records: BreathRecords
    @EnvironmentObject private var receiver: WatchHeartReceiver
    @EnvironmentObject private var engine: BreathEngine
    @State private var sessionOpen = false
    @State private var showSafety = false
    @State private var bestMoment: TimeInterval?
    @State private var didEnd = false
    @State private var beginAfterSafety = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("PULSE")
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                    scores
                    if let imported = records.importedPersonalBest {
                        Text("New personal best \(DurationText.clock(imported))")
                            .font(.system(.callout, design: .monospaced))
                    }
                    Text(receiver.bpm.map { String(format: "%.0f BPM", $0) } ?? "-- BPM")
                        .font(.system(size: 42, weight: .light, design: .monospaced))
                        .monospacedDigit()
                    Text(receiver.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .standard))" } ?? "Start a session on your Watch")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    presetButton(.coherence, subtitle: "5.5s in  ·  5.5s out  ·  no hold", caption: "About 5.5 breaths a minute")
                    presetButton(.custom, subtitle: "Set your own inhale, hold and exhale", caption: nil)
                    presetButton(.training, subtitle: "CO2 or O2 table", caption: nil)
                    if records.setup.preset == .custom {
                        customControls
                    }
                    if records.setup.preset == .training {
                        trainingControls
                    }
                    Button("Start", action: startTapped)
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                    NavigationLink("History") {
                        HistoryList(records: records)
                    }
                    .font(.system(.body, design: .monospaced))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: receiver.bpm) { _, bpm in
            if let bpm { engine.noteHeartRate(bpm) }
        }
        .onChange(of: receiver.stopTick) { _, _ in
            guard let id = receiver.stoppedSession, engine.running, engine.sessionID == id else { return }
            endSession(notifyWatch: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.catchUp() }
        }
        .onChange(of: receiver.startTick) { _, _ in
            guard let start = receiver.remoteStart, start.origin != "phone", !engine.running, !sessionOpen else { return }
            didEnd = false
            bestMoment = nil
            records.importedPersonalBest = nil
            engine.start(
                at: start.startedAt,
                rounds: start.rounds,
                repeats: start.repeats,
                label: start.label,
                origin: start.origin,
                personalBest: records.personalBest,
                sessionID: start.id
            )
            sessionOpen = true
        }
        .sheet(isPresented: $showSafety, onDismiss: {
            if beginAfterSafety {
                beginAfterSafety = false
                begin()
            }
        }) {
            SafetySheet {
                records.acknowledgeSafety()
                beginAfterSafety = true
                showSafety = false
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $sessionOpen) {
            SessionCover(
                engine: engine,
                bpm: receiver.bpm,
                personalBest: bestMoment,
                onStop: { endSession(notifyWatch: true) },
                onDone: {
                    bestMoment = nil
                    sessionOpen = false
                }
            )
        }
    }

    private var scores: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PERSONAL BEST")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(records.personalBest > 0 ? DurationText.clock(records.personalBest) : "—")
                    .font(.system(size: 28, weight: .light, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("STREAK")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(records.streak > 0 ? "\(records.streak)d" : "—")
                    .font(.system(size: 28, weight: .light, design: .monospaced))
            }
        }
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            durationRow("In", value: records.setup.inhale, minimum: 1) { records.setup.inhale = $0 }
            durationRow("Hold", value: records.setup.hold, minimum: 0) { records.setup.hold = $0 }
            HStack(spacing: 8) {
                ForEach([30.0, 60.0, 120.0, 180.0], id: \.self) { seconds in
                    Button(DurationText.clock(seconds)) {
                        records.setup.hold = seconds
                        records.saveSetup()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(.caption, design: .monospaced))
                }
            }
            durationRow("Out", value: records.setup.exhale, minimum: 1) { records.setup.exhale = $0 }
            Text("No limit on the hold. Two and three minutes are normal here.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var trainingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Table", selection: trainingKind) {
                ForEach(TrainingKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            Text(records.setup.trainingKind.detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            durationRow("In", value: records.setup.inhale, minimum: 1) { records.setup.inhale = $0 }
            durationRow("Hold", value: records.setup.hold, minimum: 0) { records.setup.hold = $0 }
            durationRow(records.setup.trainingKind == .co2 ? "Rest" : "Rest", value: records.setup.rest, minimum: 5) {
                records.setup.rest = $0
            }
            durationRow("Step", value: records.setup.step, minimum: 0) { records.setup.step = $0 }
            Stepper(value: rounds, in: 1...40) {
                Text("\(records.setup.rounds) rounds")
                    .font(.system(.body, design: .monospaced))
            }
            let preview = Array(BreathTables.make(records.setup).prefix(8))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(preview.indices), id: \.self) { index in
                    let round = preview[index]
                    Text("\(index + 1)  hold \(DurationText.clock(round.hold))  rest \(DurationText.clock(round.exhale))")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var trainingKind: Binding<TrainingKind> {
        Binding(
            get: { records.setup.trainingKind },
            set: { kind in
                records.setup.trainingKind = kind
                records.saveSetup()
            }
        )
    }

    private var rounds: Binding<Int> {
        Binding(
            get: { records.setup.rounds },
            set: { value in
                records.setup.rounds = value
                records.saveSetup()
            }
        )
    }

    private func presetButton(_ preset: BreathPreset, subtitle: String, caption: String?) -> some View {
        let selected = records.setup.preset == preset
        return Button {
            records.setup.preset = preset
            records.saveSetup()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.system(preset == .coherence ? .title3 : .body, design: .monospaced))
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                if let caption {
                    Text(caption)
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(preset == .coherence ? 16 : 12)
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
            .background(selected ? Color.primary : Color.clear)
            .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func durationRow(_ title: String, value: Double, minimum: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(DurationText.clock(value))
            }
            .font(.system(.body, design: .monospaced))
            HStack(spacing: 8) {
                adjust("−15", -15, value: value, minimum: minimum, set: set)
                adjust("−1", -1, value: value, minimum: minimum, set: set)
                adjust("+1", 1, value: value, minimum: minimum, set: set)
                adjust("+15", 15, value: value, minimum: minimum, set: set)
                adjust("+1m", 60, value: value, minimum: minimum, set: set)
            }
        }
    }

    private func adjust(_ label: String, _ delta: Double, value: Double, minimum: Double, set: @escaping (Double) -> Void) -> some View {
        Button(label) {
            set(max(minimum, value + delta))
            records.saveSetup()
        }
        .buttonStyle(.bordered)
        .font(.system(.caption, design: .monospaced))
    }

    private func startTapped() {
        if records.setup.needsSafetyNotice && !records.safetyAcknowledged {
            showSafety = true
        } else {
            begin()
        }
    }

    private func begin() {
        let plan = records.setup.plan
        let started = Date()
        let id = UUID()
        didEnd = false
        bestMoment = nil
        records.importedPersonalBest = nil
        engine.start(
            at: started,
            rounds: plan.rounds,
            repeats: plan.repeats,
            label: plan.label,
            origin: "phone",
            personalBest: records.personalBest,
            sessionID: id
        )
        receiver.send(BreathLink.startPayload(
            id: id,
            startedAt: started,
            rounds: plan.rounds,
            repeats: plan.repeats,
            label: plan.label,
            origin: "phone"
        ))
        sessionOpen = true
    }

    private func endSession(notifyWatch: Bool) {
        guard !didEnd else { return }
        didEnd = true
        let log = engine.stop()
        if notifyWatch {
            receiver.send(BreathLink.stopPayload(id: log.id))
        }
        if records.commit(log) {
            records.importedPersonalBest = nil
            bestMoment = log.longestHold
            PhoneHaptics.personalBest()
        } else if let imported = records.importedPersonalBest,
                  imported > 0,
                  abs(imported - log.longestHold) < 0.5,
                  abs(imported - records.personalBest) < 0.05 {
            records.importedPersonalBest = nil
            bestMoment = imported
            PhoneHaptics.personalBest()
        } else {
            bestMoment = nil
            sessionOpen = false
        }
    }
}
