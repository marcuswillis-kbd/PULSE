import UIKit

enum PhoneHaptics {
    static func play(_ phase: BreathPhase) {
        switch phase {
        case .inhale:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.75)
        case .hold:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case .exhale:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.85)
        }
        UIAccessibility.post(notification: .announcement, argument: phase.spoken)
    }

    static func personalBest() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
