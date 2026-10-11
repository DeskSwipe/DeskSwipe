/// Trackpad gesture settings as stored by System Settings, for one
/// preferences domain (built-in or Bluetooth trackpad). `nil` means the key
/// is not present, i.e. the macOS default applies.
public struct TrackpadGesturePreferences: Equatable, Sendable {
    /// `TrackpadThreeFingerVertSwipeGesture`: 0 = off, 2 = Mission Control /
    /// App Exposé on three fingers.
    public var threeFingerVerticalSwipe: Int?
    /// `TrackpadThreeFingerDrag` (Accessibility > Pointer Control).
    public var threeFingerDrag: Bool?

    public init(threeFingerVerticalSwipe: Int? = nil, threeFingerDrag: Bool? = nil) {
        self.threeFingerVerticalSwipe = threeFingerVerticalSwipe
        self.threeFingerDrag = threeFingerDrag
    }

    public static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]
    public static let threeFingerVerticalSwipeKey = "TrackpadThreeFingerVertSwipeGesture"
    public static let threeFingerDragKey = "TrackpadThreeFingerDrag"
}

/// Dock settings that can switch the Mission Control / App Exposé gestures
/// off independently of the trackpad finger count.
public struct DockGesturePreferences: Equatable, Sendable {
    /// `showMissionControlGestureEnabled` in com.apple.dock.
    public var missionControl: Bool?
    /// `showAppExposeGestureEnabled` in com.apple.dock.
    public var appExpose: Bool?

    public init(missionControl: Bool? = nil, appExpose: Bool? = nil) {
        self.missionControl = missionControl
        self.appExpose = appExpose
    }
}

public enum GestureConflict: Equatable, Sendable, CaseIterable {
    /// macOS uses three-finger vertical swipes for Mission Control / App Exposé.
    case systemThreeFingerSwipe
    /// Three-finger drag turns three-finger movement into window drags.
    case threeFingerDrag

    public var summary: String {
        switch self {
        case .systemThreeFingerSwipe:
            return "macOS 3-finger swipes (Mission Control / App Exposé) are likely on"
        case .threeFingerDrag:
            return "Three-finger drag is on"
        }
    }

    public var fix: String {
        switch self {
        case .systemThreeFingerSwipe:
            return "System Settings > Trackpad > More Gestures: set Mission Control and App Exposé to \"Swipe Up/Down with Four Fingers\" or Off."
        case .threeFingerDrag:
            return "System Settings > Accessibility > Pointer Control > Trackpad Options: turn off \"Use trackpad for dragging\" or choose a non-three-finger drag style."
        }
    }

    /// Decide which conflicts are likely, given the stored preferences.
    ///
    /// Missing keys fall back to macOS defaults (three-finger Mission Control
    /// is on by default). A domain that lacks a key is ignored when another
    /// domain has it, since an unused Bluetooth-trackpad domain is often empty.
    public static func detect(
        trackpads: [TrackpadGesturePreferences],
        dock: DockGesturePreferences
    ) -> [GestureConflict] {
        var conflicts: [GestureConflict] = []

        let vertical = trackpads.compactMap(\.threeFingerVerticalSwipe)
        let threeFingerVerticalOn = vertical.isEmpty ? true : vertical.contains { $0 != 0 }
        let dockGesturesOff = dock.missionControl == false && dock.appExpose == false
        if threeFingerVerticalOn && !dockGesturesOff {
            conflicts.append(.systemThreeFingerSwipe)
        }

        if trackpads.contains(where: { $0.threeFingerDrag == true }) {
            conflicts.append(.threeFingerDrag)
        }
        return conflicts
    }
}

extension SwipeGesture {
    public var inverted: SwipeGesture {
        switch self {
        case .swipeDown: return .swipeUp
        case .swipeUp: return .swipeDown
        }
    }
}
