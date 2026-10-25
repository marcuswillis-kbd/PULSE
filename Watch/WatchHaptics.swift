import WatchKit

enum WatchHaptics {
    static func play(_ phase: BreathPhase) {
        let type: WKHapticType
        switch phase {
        case .inhale: type = .directionUp
        case .hold: type = .click
        case .exhale: type = .directionDown
        }
        WKInterfaceDevice.current().play(type)
    }
}
