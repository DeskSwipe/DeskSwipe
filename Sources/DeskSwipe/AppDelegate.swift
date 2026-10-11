import AppKit
import Combine
import DeskSwipeCore
import os

private let log = Logger(subsystem: "DeskSwipe", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let status = SystemStatus()
    private let multitouch = MultitouchService()
    private let windows = WindowManager()
    private var menu: StatusMenuController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenuController(settings: settings, status: status)
        menu?.onOpenSettings = { [weak self] in self?.showSettings() }

        windows.onChange = { [weak self] in
            guard let self else { return }
            self.status.update(hiddenWindowCount: self.windows.rememberedCount)
        }

        // Settings flow into the recognizer on the multitouch thread.
        settings.$enabled.combineLatest(settings.$threshold)
            .sink { [weak self] enabled, threshold in
                self?.multitouch.router.update(
                    configuration: SwipeRecognizerConfiguration(threshold: Float(threshold)),
                    enabled: enabled
                )
            }
            .store(in: &cancellables)

        multitouch.router.onGesture = { [weak self] gesture in self?.handle(gesture) }
        multitouch.onDevicesChanged = { [weak self] count in
            self?.status.update(trackpadCount: count, multitouchError: nil)
        }
        multitouch.start()
        status.update(trackpadCount: multitouch.deviceCount, multitouchError: multitouch.failure?.description)

        status.requestAccessibilityIfNeeded()
        status.refreshConflicts()
        status.refreshLaunchAtLogin()
        if !status.conflicts.isEmpty {
            log.notice("Conflicting system gestures detected: \(self.status.conflicts.map(\.summary), privacy: .public)")
        }
    }

    private func handle(_ gesture: SwipeGesture) {
        guard settings.enabled else { return }
        switch settings.invertDirection ? gesture.inverted : gesture {
        case .swipeDown: windows.showDesktop()
        case .swipeUp: windows.restore()
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, status: status)
        }
        settingsWindow?.present()
    }
}
