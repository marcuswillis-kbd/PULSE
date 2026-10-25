import SwiftUI

@main
struct PulsePhoneApp: App {
    @StateObject private var records = BreathRecords.shared
    @StateObject private var receiver = WatchHeartReceiver()
    @StateObject private var engine: BreathEngine

    init() {
        let engine = BreathEngine()
        engine.onPhase = { PhoneHaptics.play($0) }
        _engine = StateObject(wrappedValue: engine)
    }

    var body: some Scene {
        WindowGroup {
            PhoneDashboard()
                .environmentObject(records)
                .environmentObject(receiver)
                .environmentObject(engine)
        }
    }
}
