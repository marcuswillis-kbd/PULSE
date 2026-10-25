import SwiftUI
@main
struct PulsePhoneApp: App {
    @StateObject private var receiver = WatchHeartReceiver()
    var body: some Scene {
        WindowGroup { PhoneDashboard().environmentObject(receiver) }
    }
}
