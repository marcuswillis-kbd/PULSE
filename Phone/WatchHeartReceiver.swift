import Foundation
import WatchConnectivity

final class WatchHeartReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var bpm: Double?
    @Published var updatedAt: Date?
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bpm = message["bpm"] as? Double else { return }
        DispatchQueue.main.async { self.bpm = bpm; self.updatedAt = Date() }
    }
}
