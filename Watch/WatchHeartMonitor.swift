import Foundation
import HealthKit
import WatchConnectivity

final class WatchHeartMonitor: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    @Published var bpm: Double?
    @Published var active = false
    @Published var status = "Ready"
    private let store = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
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
        } catch { status = error.localizedDescription }
    }
    func stop() {
        guard let workout, let builder else { return }
        workout.end()
        builder.endCollection(withEnd: Date()) { [weak self] _, _ in
            builder.discardWorkout()
            DispatchQueue.main.async {
                self?.active = false
                self?.status = "Stopped"
            }
        }
    }
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartType),
              let bpm = workoutBuilder.statistics(for: heartType)?
                .mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        DispatchQueue.main.async { self.bpm = bpm }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["bpm": bpm], replyHandler: nil, errorHandler: nil)
        }
    }
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.active = false
            self.status = error.localizedDescription
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
