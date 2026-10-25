import Combine
import Foundation

enum BreathPhase: String, Codable, Equatable {
    case inhale
    case hold
    case exhale

    var label: String {
        switch self {
        case .inhale: return "IN"
        case .hold: return "HOLD"
        case .exhale: return "OUT"
        }
    }

    var spoken: String {
        switch self {
        case .inhale: return "In"
        case .hold: return "Hold"
        case .exhale: return "Out"
        }
    }
}

struct BreathRound: Codable, Equatable {
    var inhale: TimeInterval
    var hold: TimeInterval
    var exhale: TimeInterval

    var total: TimeInterval { max(0, inhale) + max(0, hold) + max(0, exhale) }

    /// HeartMath-style resonance breathing: about 5.5 breaths a minute, no hold.
    static let coherence = BreathRound(inhale: 5.5, hold: 0, exhale: 5.5)

    static func locate(_ round: BreathRound, offset: TimeInterval) -> (phase: BreathPhase, startOffset: TimeInterval, duration: TimeInterval) {
        let inhale = max(0, round.inhale)
        let hold = max(0, round.hold)
        let exhale = max(0, round.exhale)
        var cursor = max(0, offset)
        if inhale > 0 {
            if cursor < inhale { return (.inhale, 0, inhale) }
            cursor -= inhale
        }
        if hold > 0 {
            if cursor < hold { return (.hold, inhale, hold) }
            cursor -= hold
        }
        if exhale > 0 {
            return (.exhale, inhale + hold, exhale)
        }
        if hold > 0 { return (.hold, inhale, hold) }
        return (.inhale, 0, max(inhale, 0.001))
    }
}

enum BreathPreset: String, Codable, CaseIterable, Identifiable {
    case coherence
    case custom
    case training

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coherence: return "Coherence"
        case .custom: return "Custom"
        case .training: return "Training"
        }
    }
}

enum TrainingKind: String, Codable, CaseIterable, Identifiable {
    case co2
    case o2

    var id: String { rawValue }
    var title: String { self == .co2 ? "CO2" : "O2" }

    var detail: String {
        switch self {
        case .co2: return "Hold stays put. Rest gets shorter each round."
        case .o2: return "Rest stays put. Hold gets longer each round."
        }
    }
}

struct BreathSetup: Codable, Equatable {
    var preset: BreathPreset = .coherence
    var inhale: Double = 4
    var hold: Double = 20
    var exhale: Double = 6
    var trainingKind: TrainingKind = .co2
    var rounds: Int = 8
    var step: Double = 15
    var rest: Double = 120

    var plan: (rounds: [BreathRound], repeats: Bool, label: String) {
        switch preset {
        case .coherence:
            return ([.coherence], true, "Coherence")
        case .custom:
            let round = BreathRound(inhale: max(1, inhale), hold: max(0, hold), exhale: max(1, exhale))
            return ([round], true, "Custom")
        case .training:
            let table = BreathTables.make(self)
            let label = trainingKind == .co2 ? "CO2" : "O2"
            return (table, false, label)
        }
    }

    var longestPlannedHold: TimeInterval {
        plan.rounds.map(\.hold).max() ?? 0
    }

    var needsSafetyNotice: Bool {
        preset == .training || longestPlannedHold >= 60
    }
}

enum BreathTables {
    static func make(_ setup: BreathSetup) -> [BreathRound] {
        let count = min(40, max(1, setup.rounds))
        let inhale = max(1, setup.inhale)
        let hold = max(0, setup.hold)
        let rest = max(5, setup.rest)
        let step = max(0, setup.step)
        return (0..<count).map { index in
            switch setup.trainingKind {
            case .co2:
                return BreathRound(inhale: inhale, hold: hold, exhale: max(5, rest - step * Double(index)))
            case .o2:
                return BreathRound(inhale: inhale, hold: hold + step * Double(index), exhale: rest)
            }
        }
    }
}

struct PhaseRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: BreathPhase
    var startedAt: Date
    var endedAt: Date?
    var plannedSeconds: TimeInterval
}

struct HeartSample: Codable, Equatable {
    /// Seconds from the start of the session. Only real Watch readings are stored.
    var offset: TimeInterval
    var bpm: Double
}

struct SessionLog: Codable, Equatable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var longestHold: TimeInterval
    var label: String
    var repeats: Bool
    var rounds: Int
    var phases: [PhaseRecord]
    var heartSamples: [HeartSample]
    var origin: String
}

enum DurationText {
    static func clock(_ seconds: TimeInterval) -> String {
        let safe = max(0, seconds)
        if safe >= 60 {
            let total = Int(safe.rounded(.down))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        if abs(safe.rounded() - safe) > 0.05 {
            return String(format: "%.1f", safe)
        }
        return String(format: "%.0f", safe.rounded())
    }

    static func countdown(remaining: TimeInterval, phaseDuration: TimeInterval) -> String {
        let safe = max(0, remaining)
        if phaseDuration >= 60 || safe >= 60 {
            let total = Int(ceil(safe - 0.001))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        if abs(phaseDuration.rounded() - phaseDuration) > 0.05 {
            let tenths = (safe * 10).rounded() / 10
            return String(format: "%.1f", max(0, tenths))
        }
        return String(max(0, Int(ceil(safe - 0.001))))
    }
}

final class BreathRecords: ObservableObject {
    static let shared = BreathRecords()

    @Published private(set) var personalBest: TimeInterval = 0
    @Published private(set) var streak: Int = 0
    @Published private(set) var history: [SessionLog] = []
    @Published private(set) var safetyAcknowledged = false
    @Published var setup = BreathSetup()
    @Published var importedPersonalBest: TimeInterval?

    private var seen: [String] = []
    private var lastDay: String?
    private let defaults = UserDefaults.standard

    private init() {
        personalBest = defaults.double(forKey: Key.best)
        streak = defaults.integer(forKey: Key.streak)
        lastDay = defaults.string(forKey: Key.day)
        safetyAcknowledged = defaults.bool(forKey: Key.safety)
        seen = defaults.stringArray(forKey: Key.seen) ?? []
        if let data = defaults.data(forKey: Key.history),
           let logs = try? JSONDecoder().decode([SessionLog].self, from: data) {
            history = logs
        }
        if let data = defaults.data(forKey: Key.setup),
           let stored = try? JSONDecoder().decode(BreathSetup.self, from: data) {
            setup = stored
        }
    }

    func acknowledgeSafety() {
        safetyAcknowledged = true
        defaults.set(true, forKey: Key.safety)
    }

    func saveSetup() {
        if let data = try? JSONEncoder().encode(setup) {
            defaults.set(data, forKey: Key.setup)
        }
    }

    @discardableResult
    func commit(_ log: SessionLog) -> Bool {
        guard remember(log.id) else { return false }
        let isNew = log.longestHold > personalBest && log.longestHold > 0
        if isNew { personalBest = log.longestHold }
        register(log.endedAt)
        history.insert(log, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        persist()
        return isNew
    }

    @discardableResult
    func importLog(_ log: SessionLog) -> Bool {
        let isNew = commit(log)
        if isNew { importedPersonalBest = log.longestHold }
        return isNew
    }

    private func remember(_ id: UUID) -> Bool {
        let key = id.uuidString
        guard !seen.contains(key) else { return false }
        seen.append(key)
        if seen.count > 100 { seen.removeFirst(seen.count - 100) }
        return true
    }

    private func register(_ date: Date) {
        let day = Self.dayString(date)
        if day == lastDay { return }
        if let lastDay, let previous = Self.date(from: lastDay),
           let next = Calendar.current.date(byAdding: .day, value: 1, to: previous),
           Self.dayString(next) == day {
            streak += 1
        } else {
            streak = 1
        }
        self.lastDay = day
    }

    private func persist() {
        defaults.set(personalBest, forKey: Key.best)
        defaults.set(streak, forKey: Key.streak)
        defaults.set(lastDay, forKey: Key.day)
        defaults.set(seen, forKey: Key.seen)
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Key.history)
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    private enum Key {
        static let best = "pulse.personalBest"
        static let streak = "pulse.streak"
        static let day = "pulse.lastDay"
        static let history = "pulse.history"
        static let safety = "pulse.safetyAcknowledged"
        static let setup = "pulse.setup"
        static let seen = "pulse.seenSessions"
    }
}
