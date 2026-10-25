import Combine
import Foundation
import HealthKit
import WatchConnectivity

final class WatchHeartMonitor: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    @Published var bpm: Double?
    @Published var active = false
    @Published var status = "Coherence"
    let guide = BreathEngine()
    private let store = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var queue: [[String: Any]] = []
    private var didReport = false

    override init() {
        super.init()
        guide.onPhase = { WatchHaptics.play($0) }
        guide.onFinished = { [weak self] in
            self?.guideFinished()
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func userStart() {
        didReport = false
        let started = Date()
        let id = UUID()
        guide.start(
            at: started,
            rounds: [.coherence],
            repeats: true,
            label: "Coherence",
            origin: "watch",
            personalBest: 0,
            sessionID: id
        )
        start()
        send(BreathLink.startPayload(
            id: id,
            startedAt: started,
            rounds: [.coherence],
            repeats: true,
            label: "Coherence",
            origin: "watch"
        ))
    }

    func userStop() {
        report(sendResult: guide.origin == "watch")
    }

    private func guideFinished() {
        if guide.origin == "watch" {
            report(sendResult: true)
        } else {
            didReport = true
            _ = guide.stop()
            stop()
        }
    }

    private func report(sendResult: Bool) {
        guard !didReport else {
            _ = guide.stop()
            stop()
            return
        }
        didReport = true
        let log = guide.stop()
        stop()
        send(BreathLink.stopPayload(id: log.id))
        if sendResult {
            send(BreathLink.resultPayload(log))
        }
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            status = "Health data unavailable"
            return
        }
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heartType]) { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed else {
                    self.status = error?.localizedDescription ?? "Health access not granted"
                    return
                }
                self.beginWorkout()
            }
        }
    }

    private func beginWorkout() {
        guard workout == nil else { return }
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .mindAndBody
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let live = session.associatedWorkoutBuilder()
            session.delegate = self
            live.delegate = self
            live.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            workout = session
            builder = live
            let now = Date()
            session.startActivity(with: now)
            live.beginCollection(withStart: now) { [weak self] ok, error in
                DispatchQueue.main.async {
                    self?.active = ok
                    self?.status = ok ? "Reading heart rate" : (error?.localizedDescription ?? "Failed to start")
                }
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func stop() {
        guard let workout, let builder else { return }
        workout.end()
        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder.discardWorkout()
            DispatchQueue.main.async {
                self?.workout = nil
                self?.builder = nil
                self?.active = false
                self?.status = "Coherence"
            }
        }
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartType),
              let bpm = workoutBuilder.statistics(for: heartType)?
                .mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
              bpm.isFinite, bpm > 0 else { return }
        DispatchQueue.main.async {
            self.bpm = bpm
            self.guide.noteHeartRate(bpm)
        }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["bpm": bpm], replyHandler: nil, errorHandler: nil)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.active = false
            self.workout = nil
            self.builder = nil
            self.status = error.localizedDescription
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        flush(session)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    private func handle(_ message: [String: Any]) {
        DispatchQueue.main.async {
            switch BreathLink.decode(message) {
            case .start(let id, let startedAt, let rounds, let repeats, let label, let origin):
                if self.guide.running, self.guide.origin == "watch" {
                    self.report(sendResult: true)
                }
                self.didReport = false
                self.guide.start(
                    at: startedAt,
                    rounds: rounds,
                    repeats: repeats,
                    label: label,
                    origin: origin,
                    personalBest: 0,
                    sessionID: id
                )
                if !self.active { self.start() }
            case .stop(let id):
                if self.guide.running, self.guide.sessionID != id { return }
                self.didReport = true
                _ = self.guide.stop()
                self.stop()
            default:
                break
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        queue.append(payload)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        flush(session)
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
}
