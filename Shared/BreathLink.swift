import Foundation

enum BreathCommand {
    case start(id: UUID, startedAt: Date, rounds: [BreathRound], repeats: Bool, label: String, origin: String)
    case stop(id: UUID)
    case result(SessionLog)
    case heartRate(Double)
}

enum BreathLink {
    static func startPayload(
        id: UUID,
        startedAt: Date,
        rounds: [BreathRound],
        repeats: Bool,
        label: String,
        origin: String
    ) -> [String: Any] {
        [
            "cmd": "start",
            "id": id.uuidString,
            "startedAt": startedAt.timeIntervalSince1970,
            "repeat": repeats,
            "label": label,
            "origin": origin,
            "rounds": rounds.map { [$0.inhale, $0.hold, $0.exhale] },
        ]
    }

    static func stopPayload(id: UUID) -> [String: Any] {
        ["cmd": "stop", "id": id.uuidString]
    }

    static func resultPayload(_ log: SessionLog) -> [String: Any] {
        [
            "cmd": "result",
            "id": log.id.uuidString,
            "startedAt": log.startedAt.timeIntervalSince1970,
            "endedAt": log.endedAt.timeIntervalSince1970,
            "longestHold": log.longestHold,
            "label": log.label,
            "repeat": log.repeats,
            "rounds": log.rounds,
            "origin": log.origin,
            "phases": log.phases.prefix(300).map { phase -> [Any] in
                [
                    phase.kind.rawValue,
                    phase.startedAt.timeIntervalSince1970,
                    (phase.endedAt ?? phase.startedAt).timeIntervalSince1970,
                    phase.plannedSeconds,
                    phase.id.uuidString,
                ]
            },
            "heart": log.heartSamples.prefix(500).map { [$0.offset, $0.bpm] },
        ]
    }

    static func decode(_ message: [String: Any]) -> BreathCommand {
        if let bpm = number(message["bpm"]), message["cmd"] == nil {
            return .heartRate(bpm)
        }
        guard let cmd = message["cmd"] as? String else { return .heartRate(number(message["bpm"]) ?? -1) }
        switch cmd {
        case "start":
            guard let id = uuid(message["id"]), let rounds = rounds(message["rounds"]), !rounds.isEmpty else { break }
            let started = Date(timeIntervalSince1970: number(message["startedAt"]) ?? Date().timeIntervalSince1970)
            return .start(
                id: id,
                startedAt: started,
                rounds: rounds,
                repeats: flag(message["repeat"]) ?? true,
                label: message["label"] as? String ?? "Custom",
                origin: message["origin"] as? String ?? "phone"
            )
        case "stop":
            if let id = uuid(message["id"]) { return .stop(id: id) }
        case "result":
            if let log = log(message) { return .result(log) }
        default:
            break
        }
        if let bpm = number(message["bpm"]), bpm > 0 { return .heartRate(bpm) }
        return .heartRate(-1)
    }

    private static func rounds(_ value: Any?) -> [BreathRound]? {
        guard let rows = value as? [Any] else { return nil }
        let parsed = rows.compactMap { row -> BreathRound? in
            guard let values = numbers(row), values.count == 3 else { return nil }
            return BreathRound(inhale: values[0], hold: values[1], exhale: values[2])
        }
        return parsed.isEmpty ? nil : parsed
    }

    private static func log(_ message: [String: Any]) -> SessionLog? {
        guard let id = uuid(message["id"]) else { return nil }
        let started = Date(timeIntervalSince1970: number(message["startedAt"]) ?? Date().timeIntervalSince1970)
        let ended = Date(timeIntervalSince1970: number(message["endedAt"]) ?? started.timeIntervalSince1970)
        let phases = (message["phases"] as? [Any] ?? []).compactMap { item -> PhaseRecord? in
            guard let values = item as? [Any], values.count >= 4,
                  let kindName = values[0] as? String, let kind = BreathPhase(rawValue: kindName) else { return nil }
            let start = Date(timeIntervalSince1970: number(values[1]) ?? started.timeIntervalSince1970)
            let end = Date(timeIntervalSince1970: number(values[2]) ?? start.timeIntervalSince1970)
            let planned = number(values[3]) ?? end.timeIntervalSince(start)
            let phaseID = values.count > 4 ? uuid(values[4]) ?? UUID() : UUID()
            return PhaseRecord(id: phaseID, kind: kind, startedAt: start, endedAt: end, plannedSeconds: planned)
        }
        let hearts = (message["heart"] as? [Any] ?? []).compactMap { item -> HeartSample? in
            guard let values = numbers(item), values.count == 2, values[1] > 0 else { return nil }
            return HeartSample(offset: values[0], bpm: values[1])
        }
        return SessionLog(
            id: id,
            startedAt: started,
            endedAt: ended,
            longestHold: number(message["longestHold"]) ?? 0,
            label: message["label"] as? String ?? "Watch",
            repeats: flag(message["repeat"]) ?? true,
            rounds: Int(number(message["rounds"]) ?? 1),
            phases: phases,
            heartSamples: hearts,
            origin: message["origin"] as? String ?? "watch"
        )
    }

    private static func numbers(_ value: Any?) -> [Double]? {
        if let values = value as? [Double] { return values }
        if let values = value as? [NSNumber] { return values.map(\.doubleValue) }
        if let values = value as? [Any] {
            let parsed = values.compactMap { number($0) }
            return parsed.count == values.count ? parsed : nil
        }
        return nil
    }

    private static func flag(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func uuid(_ value: Any?) -> UUID? {
        guard let text = value as? String else { return nil }
        return UUID(uuidString: text)
    }
}
