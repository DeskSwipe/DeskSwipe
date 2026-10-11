import AppKit
import ApplicationServices
import DeskSwipeCore
import ServiceManagement
import os

private let log = Logger(subsystem: "DeskSwipe", category: "Status")

/// Live view of things outside our control: permissions, devices, conflicting
/// system gestures and the login item. Main thread only.
final class SystemStatus: ObservableObject {
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var conflicts: [GestureConflict] = []
    @Published private(set) var trackpadCount = 0
    @Published private(set) var multitouchError: String?
    @Published private(set) var hiddenWindowCount = 0
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @Published var launchAtLoginError: String?

    private var accessibilityTimer: Timer?

    // MARK: Accessibility

    /// Shows the system prompt if we are not trusted yet, then polls until
    /// permission is granted (there is no notification for it).
    func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted { startPollingAccessibility() }
    }

    func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        if granted != accessibilityGranted { accessibilityGranted = granted }
        if !granted { startPollingAccessibility() }
    }

    private func startPollingAccessibility() {
        guard accessibilityTimer == nil else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if AXIsProcessTrusted() {
                self.accessibilityGranted = true
                timer.invalidate()
                self.accessibilityTimer = nil
                log.info("Accessibility permission granted")
            }
        }
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openTrackpadSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    // MARK: Gesture conflicts

    func refreshConflicts() {
        let trackpads = TrackpadGesturePreferences.domains.map { domain -> TrackpadGesturePreferences in
            CFPreferencesAppSynchronize(domain as CFString)
            return TrackpadGesturePreferences(
                threeFingerVerticalSwipe: Self.preference(TrackpadGesturePreferences.threeFingerVerticalSwipeKey, domain) as? Int,
                threeFingerDrag: Self.preference(TrackpadGesturePreferences.threeFingerDragKey, domain) as? Bool
            )
        }
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let dock = DockGesturePreferences(
            missionControl: Self.preference("showMissionControlGestureEnabled", "com.apple.dock") as? Bool,
            appExpose: Self.preference("showAppExposeGestureEnabled", "com.apple.dock") as? Bool
        )
        let detected = GestureConflict.detect(trackpads: trackpads, dock: dock)
        if detected != conflicts { conflicts = detected }
    }

    private static func preference(_ key: String, _ domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    // MARK: Devices and windows

    func update(trackpadCount: Int, multitouchError: String?) {
        self.trackpadCount = trackpadCount
        self.multitouchError = multitouchError
    }

    func update(hiddenWindowCount: Int) {
        if hiddenWindowCount != self.hiddenWindowCount { self.hiddenWindowCount = hiddenWindowCount }
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not update login item: \(error.localizedDescription)"
            log.error("SMAppService error: \(error.localizedDescription, privacy: .public)")
        }
        refreshLaunchAtLogin()
    }

    func refreshAll() {
        refreshAccessibility()
        refreshConflicts()
        refreshLaunchAtLogin()
    }
}
