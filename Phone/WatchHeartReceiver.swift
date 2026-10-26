import Foundation
import WatchConnectivity

struct HeartPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let bpm: Double
}

final class WatchHeartReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var bpm: Double?
    @Published var updatedAt: Date?
    @Published var points: [HeartPoint] = []
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func setBeatHaptics(_ enabled: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(["beatHaptics": enabled], replyHandler: nil, errorHandler: nil)
        }
        try? session.updateApplicationContext(["beatHaptics": enabled])
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bpm = message["bpm"] as? Double else { return }
        DispatchQueue.main.async {
            let now = Date()
            self.bpm = bpm
            self.updatedAt = now
            self.points.append(HeartPoint(timestamp: now, bpm: bpm))
            self.points.removeAll { now.timeIntervalSince($0.timestamp) > 180 }
        }
    }
}
