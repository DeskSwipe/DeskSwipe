import Combine
import DeskSwipeCore
import Foundation

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let threshold = "swipeThreshold"
        static let invertDirection = "invertDirection"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    /// Required vertical travel as a fraction of trackpad height.
    @Published var threshold: Double {
        didSet { defaults.set(threshold, forKey: Key.threshold) }
    }

    /// Swap the meaning of up and down.
    @Published var invertDirection: Bool {
        didSet { defaults.set(invertDirection, forKey: Key.invertDirection) }
    }

    static var thresholdRange: ClosedRange<Double> {
        let range = SwipeRecognizerConfiguration.thresholdRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.threshold: Double(SwipeRecognizerConfiguration.defaultThreshold),
            Key.invertDirection: false,
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        let range = Self.thresholdRange
        threshold = min(max(defaults.double(forKey: Key.threshold), range.lowerBound), range.upperBound)
        invertDirection = defaults.bool(forKey: Key.invertDirection)
    }
}
