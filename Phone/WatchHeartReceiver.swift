import Combine
import Foundation
import WatchConnectivity

struct RemoteStart: Equatable {
    var id: UUID
    var startedAt: Date
    var rounds: [BreathRound]
    var repeats: Bool
    var label: String
    var origin: String
}

final class WatchHeartReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var bpm: Double?
    @Published var updatedAt: Date?
    @Published private(set) var stopTick = 0
    @Published private(set) var startTick = 0
    private(set) var stoppedSession: UUID?
    private(set) var remoteStart: RemoteStart?
    private var queue: [[String: Any]] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ payload: [String: Any]) {
        queue.append(payload)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        flush(session)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        flush(session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func flush(_ session: WCSession) {
        let batch = queue
        queue = []
        for payload in batch {
            deliver(payload, session: session)
        }
    }

    private func deliver(_ payload: [String: Any], session: WCSession) {
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                try? session.updateApplicationContext(payload)
            }
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    private func handle(_ message: [String: Any]) {
        DispatchQueue.main.async {
            switch BreathLink.decode(message) {
            case .heartRate(let bpm) where bpm > 0:
                self.bpm = bpm
                self.updatedAt = Date()
            case .start(let id, let startedAt, let rounds, let repeats, let label, let origin):
                self.remoteStart = RemoteStart(
                    id: id,
                    startedAt: startedAt,
                    rounds: rounds,
                    repeats: repeats,
                    label: label,
                    origin: origin
                )
                self.startTick += 1
            case .stop(let id):
                self.stoppedSession = id
                self.stopTick += 1
            case .result(let log):
                BreathRecords.shared.importLog(log)
                self.stoppedSession = log.id
                self.stopTick += 1
            default:
                break
            }
        }
    }
}
