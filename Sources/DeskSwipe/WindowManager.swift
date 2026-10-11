import AppKit
import ApplicationServices
import DeskSwipeCore
import os

private let log = Logger(subsystem: "DeskSwipe", category: "Windows")

/// A window seen through the Accessibility API, tagged with its owner's PID.
struct AXWindow: Hashable {
    let element: AXUIElement
    let pid: pid_t

    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

/// Accessibility-backed implementation of `WindowControlling`.
/// Main thread only (observer callbacks are delivered on the main run loop).
final class AXWindowController: WindowControlling {
    /// Called when a tracked window is restored or closed by someone else.
    var onTrackedWindowChangedExternally: ((AXWindow) -> Void)?

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var observers: [pid_t: AXObserver] = [:]
    private var trackedCount: [pid_t: Int] = [:]

    private static let watchedNotifications: [CFString] = [
        kAXWindowDeminiaturizedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
    ]

    init() {
        // Default is ~6 s; a hung app should not freeze the menu bar that long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    }

    // MARK: WindowControlling

    func currentWindows() -> [AXWindow] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
        }
        return Self.frontToBack(apps).flatMap { app -> [AXWindow] in
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let elements = value as? [AXUIElement] else { return [] }
            return elements.map { AXWindow(element: $0, pid: pid) }
        }
    }

    func state(of window: AXWindow) -> WindowState {
        guard window.pid != ownPID,
              NSRunningApplication(processIdentifier: window.pid) != nil else { return .gone }

        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(window.element, kAXMinimizedAttribute as CFString, &value) {
        case .success:
            break
        case .attributeUnsupported, .noValue:
            return .ignored
        default:
            // .invalidUIElement (closed), .cannotComplete (app gone/hung), ...
            return .gone
        }
        if (value as? Bool) == true { return .minimized }

        // Full-screen windows cannot be minimized; skip them silently.
        if boolAttribute(window.element, "AXFullScreen") == true { return .ignored }

        if let subrole = stringAttribute(window.element, kAXSubroleAttribute),
           subrole == kAXFloatingWindowSubrole as String || subrole == kAXSystemFloatingWindowSubrole as String {
            return .ignored
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window.element, kAXMinimizedAttribute as CFString, &settable) == .success,
              settable.boolValue else { return .ignored }

        return .visible
    }

    func setMinimized(_ window: AXWindow, _ minimized: Bool) -> Bool {
        let value = minimized ? kCFBooleanTrue : kCFBooleanFalse
        let result = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, value!)
        if result != .success {
            log.debug("Could not set minimized=\(minimized) for pid \(window.pid): \(result.rawValue)")
        }
        return result == .success
    }

    func didStartTracking(_ window: AXWindow) {
        guard let observer = observer(for: window.pid) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.watchedNotifications {
            AXObserverAddNotification(observer, window.element, name, refcon)
        }
        trackedCount[window.pid, default: 0] += 1
    }

    func didStopTracking(_ window: AXWindow) {
        guard let observer = observers[window.pid] else { return }
        for name in Self.watchedNotifications {
            AXObserverRemoveNotification(observer, window.element, name)
        }
        let remaining = (trackedCount[window.pid] ?? 1) - 1
        if remaining <= 0 {
            removeObserver(for: window.pid)
        } else {
            trackedCount[window.pid] = remaining
        }
    }

    /// Tear down everything for an app that quit.
    func appTerminated(_ pid: pid_t) {
        removeObserver(for: pid)
    }

    // MARK: Observers

    private func observer(for pid: pid_t) -> AXObserver? {
        if let existing = observers[pid] { return existing }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<AXWindowController>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            controller.onTrackedWindowChangedExternally?(AXWindow(element: element, pid: pid))
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            log.debug("AXObserverCreate failed for pid \(pid)")
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observers[pid] = created
        return created
    }

    private func removeObserver(for pid: pid_t) {
        trackedCount[pid] = nil
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    // MARK: Helpers

    /// Order apps by their frontmost on-screen window, so minimizing goes
    /// front to back and restoring (back to front) recreates the stacking.
    /// Only reads owner PIDs, which needs no Screen Recording permission.
    private static func frontToBack(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return apps }
        var rank: [pid_t: Int] = [:]
        for (index, window) in info.enumerated() {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  rank[pid] == nil else { continue }
            rank[pid] = index
        }
        return apps.enumerated()
            .sorted { (rank[$0.element.processIdentifier] ?? Int.max, $0.offset)
                    < (rank[$1.element.processIdentifier] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// App-facing entry point: show desktop / restore, plus bookkeeping for
/// windows restored from the Dock and apps that quit. Main thread only.
final class WindowManager {
    /// Called after the remembered list changes.
    var onChange: (() -> Void)?

    private let backend = AXWindowController()
    private lazy var desktop = ShowDesktopController(controller: backend)
    private var terminationObserver: NSObjectProtocol?

    var rememberedCount: Int { desktop.remembered.count }

    init() {
        backend.onTrackedWindowChangedExternally = { [weak self] window in
            self?.desktop.forget(window)
            self?.onChange?()
        }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            self.desktop.forget { $0.pid == pid }
            self.backend.appTerminated(pid)
            self.onChange?()
        }
    }

    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func showDesktop() {
        guard AXIsProcessTrusted() else {
            log.notice("Swipe down ignored: Accessibility permission missing")
            return
        }
        let count = desktop.showDesktop()
        log.info("Minimized \(count) window(s); remembering \(self.rememberedCount)")
        onChange?()
    }

    func restore() {
        guard AXIsProcessTrusted() else { return }
        let count = desktop.restore()
        log.info("Restored \(count) window(s)")
        onChange?()
    }
}
