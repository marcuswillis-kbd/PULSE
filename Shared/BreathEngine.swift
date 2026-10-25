import Combine
import Foundation

/// Runs one guided session.
///
/// The log rebuilds every phase from the planned rounds when the session
/// ends: absolute start, absolute end, and planned length. Real Watch
/// readings are stored as seconds from `startedAt`. A later wave can sit
/// on that timeline. This type does not score coherence.
final class BreathEngine: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var finishedNaturally = false
    @Published private(set) var phase: BreathPhase = .inhale
    @Published private(set) var phaseStart = Date()
    @Published private(set) var phaseEnd = Date()
    @Published private(set) var phaseDuration: TimeInterval = 1
    @Published private(set) var roundIndex = 0
    @Published private(set) var longestHold: TimeInterval = 0

    private(set) var sessionID = UUID()
    private(set) var sessionStart = Date()
    private(set) var label = "Coherence"
    private(set) var origin = "phone"
    var onPhase: ((BreathPhase) -> Void)?
    var onFinished: (() -> Void)?

    private var rounds: [BreathRound] = [.coherence]
    private var repeats = true
    private var heartSamples: [HeartSample] = []
    private var personalBestAtStart: TimeInterval = 0
    private var timer: Timer?
    private var lastHapticPhase: BreathPhase?
    private var lastHapticAt: Date?
    private var scheduledEnd: Date?
    private var stoppedLog: SessionLog?

    func start(
        at startedAt: Date,
        rounds: [BreathRound],
        repeats: Bool,
        label: String,
        origin: String,
        personalBest: TimeInterval,
        sessionID: UUID = UUID()
    ) {
        timer?.invalidate()
        let usable = rounds.filter { $0.total > 0 }
        self.rounds = usable.isEmpty ? [.coherence] : usable
        self.repeats = repeats && self.rounds.count == 1
        self.label = label
        self.origin = origin
        self.sessionID = sessionID
        self.sessionStart = startedAt
        self.personalBestAtStart = personalBest
        self.longestHold = 0
        self.heartSamples = []
        self.lastHapticPhase = nil
        self.lastHapticAt = nil
        self.scheduledEnd = nil
        self.stoppedLog = nil
        self.finishedNaturally = false
        self.running = true
        place(at: Date(), haptic: true)
    }

    /// Jump the on-screen phase to the clock. The saved log does not depend on this.
    func catchUp() {
        guard running else { return }
        place(at: Date(), haptic: true)
    }

    func noteHeartRate(_ bpm: Double, at date: Date = Date()) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.noteHeartRate(bpm, at: date) }
            return
        }
        guard running, bpm.isFinite, bpm > 0 else { return }
        let offset = max(0, date.timeIntervalSince(sessionStart))
        if let last = heartSamples.last, offset - last.offset < 0.8 { return }
        heartSamples.append(HeartSample(offset: offset, bpm: bpm))
        if heartSamples.count > 4000 { heartSamples.removeFirst(heartSamples.count - 4000) }
    }

    func stop() -> SessionLog {
        if let stoppedLog { return stoppedLog }
        timer?.invalidate()
        timer = nil
        running = false
        let ended = scheduledEnd ?? Date()
        let built = buildPhases(endedAt: ended)
        longestHold = built.longest
        let log = makeLog(endedAt: ended, phases: built.phases, roundCount: built.rounds)
        stoppedLog = log
        return log
    }

    var beatPersonalBest: Bool {
        longestHold > personalBestAtStart && longestHold > 0
    }

    private func tick() {
        guard running else { return }
        place(at: Date(), haptic: true)
    }

    private func place(at now: Date, haptic: Bool) {
        guard running else { return }
        let elapsed = max(0, now.timeIntervalSince(sessionStart))
        let total = rounds.reduce(0) { $0 + $1.total }
        guard total > 0 else {
            finish(at: now)
            return
        }
        if !repeats && elapsed >= total - 0.000_001 {
            finish(at: sessionStart.addingTimeInterval(total))
            return
        }

        let index: Int
        let into: TimeInterval
        let roundStart: Date
        if repeats {
            let cycle = rounds[0].total
            let loops = Int(elapsed / cycle)
            into = elapsed - Double(loops) * cycle
            index = 0
            roundStart = sessionStart.addingTimeInterval(Double(loops) * cycle)
            roundIndex = loops
        } else {
            var cursor = 0.0
            var found = 0
            var offset = 0.0
            for (item, round) in rounds.enumerated() {
                if elapsed < cursor + round.total || item == rounds.count - 1 {
                    found = item
                    offset = max(0, elapsed - cursor)
                    break
                }
                cursor += round.total
            }
            index = found
            into = offset
            roundStart = sessionStart.addingTimeInterval(elapsed - into)
            roundIndex = found
        }

        let round = rounds[index]
        let capped = min(into, max(round.total - 0.000_001, 0))
        let located = BreathRound.locate(round, offset: capped)
        let start = roundStart.addingTimeInterval(located.startOffset)
        phase = located.phase
        phaseStart = start
        phaseEnd = start.addingTimeInterval(located.duration)
        phaseDuration = located.duration
        scheduleTimer()
        guard haptic else { return }
        let samePulse = lastHapticPhase == located.phase && abs((lastHapticAt ?? .distantPast).timeIntervalSince(start)) < 0.2
        if !samePulse {
            lastHapticPhase = located.phase
            lastHapticAt = start
            onPhase?(located.phase)
        }
    }

    private func finish(at date: Date) {
        scheduledEnd = date
        running = false
        finishedNaturally = true
        timer?.invalidate()
        timer = nil
        onFinished?()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = phaseEnd.timeIntervalSinceNow
        if interval <= 0.01 {
            DispatchQueue.main.async { [weak self] in self?.tick() }
            return
        }
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.tick()
        }
        next.tolerance = min(0.05, interval * 0.05)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func buildPhases(endedAt end: Date) -> (phases: [PhaseRecord], longest: TimeInterval, rounds: Int) {
        var phases: [PhaseRecord] = []
        var longest: TimeInterval = 0
        var cursor = sessionStart
        let limit = 2000

        func append(kind: BreathPhase, duration: TimeInterval) -> Bool {
            if phases.count >= limit { return false }
            if duration <= 0 { return true }
            if cursor >= end { return false }
            let plannedEnd = cursor.addingTimeInterval(duration)
            let actualEnd = min(plannedEnd, end)
            phases.append(PhaseRecord(
                id: UUID(),
                kind: kind,
                startedAt: cursor,
                endedAt: actualEnd,
                plannedSeconds: duration
            ))
            if kind == .hold {
                longest = max(longest, actualEnd.timeIntervalSince(cursor))
            }
            cursor = plannedEnd
            return cursor < end
        }

        if repeats {
            let round = rounds[0]
            while phases.count < limit && cursor < end {
                let before = cursor
                if !append(kind: .inhale, duration: round.inhale) { break }
                if !append(kind: .hold, duration: round.hold) { break }
                if !append(kind: .exhale, duration: round.exhale) { break }
                if cursor <= before { break }
            }
        } else {
            for round in rounds {
                if cursor >= end || phases.count >= limit { break }
                if !append(kind: .inhale, duration: round.inhale) { break }
                if !append(kind: .hold, duration: round.hold) { break }
                if !append(kind: .exhale, duration: round.exhale) { break }
            }
        }

        let roundCount: Int
        if repeats {
            let cycle = max(rounds[0].total, 0.001)
            let elapsed = max(0, end.timeIntervalSince(sessionStart))
            roundCount = max(1, Int(ceil(elapsed / cycle - 0.000_000_1)))
        } else {
            roundCount = rounds.count
        }
        return (phases, longest, roundCount)
    }

    private func makeLog(endedAt: Date, phases: [PhaseRecord], roundCount: Int) -> SessionLog {
        SessionLog(
            id: sessionID,
            startedAt: sessionStart,
            endedAt: endedAt,
            longestHold: longestHold,
            label: label,
            repeats: repeats,
            rounds: roundCount,
            phases: phases,
            heartSamples: heartSamples,
            origin: origin
        )
    }
}
