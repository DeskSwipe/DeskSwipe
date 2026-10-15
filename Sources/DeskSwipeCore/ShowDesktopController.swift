/// What the controller needs to know about a window right now.
public enum WindowState: Equatable, Sendable {
    /// On screen and can be minimized.
    case visible
    case minimized
    /// Exists but must not be touched (full screen, not minimizable, ...).
    case ignored
    /// The window or its app no longer exists, or cannot be queried.
    case gone
}

/// Abstracts the platform window API so the bookkeeping can be unit tested.
public protocol WindowControlling: AnyObject {
    associatedtype Window: Hashable

    /// Candidate windows, frontmost first. Implementations exclude this
    /// app's own windows.
    func currentWindows() -> [Window]
    func state(of window: Window) -> WindowState
    /// Returns true if the change was applied.
    func setMinimized(_ window: Window, _ minimized: Bool) -> Bool

    /// Hooks so the platform layer can watch remembered windows for manual
    /// restores. Default implementations do nothing.
    func didStartTracking(_ window: Window)
    func didStopTracking(_ window: Window)
}

extension WindowControlling {
    public func didStartTracking(_ window: Window) {}
    public func didStopTracking(_ window: Window) {}
}

/// Remembers exactly which windows the last "show desktop" minimized so that
/// "restore" brings back only those.
///
/// - Only the most recent swipe down is remembered. A swipe down that
///   minimizes something replaces the memory; windows from earlier swipes
///   stay minimized for the user to restore from the Dock.
/// - A swipe down that minimizes nothing leaves the memory untouched.
/// - Restore brings the remembered windows back and then forgets them.
/// - Windows that were restored by other means, or whose app quit, are
///   dropped quietly (via `forget`, or lazily on the next action).
/// - Windows the user minimized themselves are never remembered, so restore
///   never touches them.
public final class ShowDesktopController<Controller: WindowControlling> {
    public typealias Window = Controller.Window

    private let controller: Controller

    /// Windows minimized by the last swipe down, frontmost first. Restore
    /// walks it back to front so the window that was in front ends up in
    /// front again.
    public private(set) var remembered: [Window] = []

    public init(controller: Controller) {
        self.controller = controller
    }

    /// Minimize every visible window. Returns how many were minimized now.
    @discardableResult
    public func showDesktop() -> Int {
        pruneStale()
        var minimized: [Window] = []
        for window in controller.currentWindows() {
            guard controller.state(of: window) == .visible,
                  controller.setMinimized(window, true) else { continue }
            minimized.append(window)
        }
        guard !minimized.isEmpty else { return 0 }
        remembered.forEach(controller.didStopTracking)
        remembered = minimized
        minimized.forEach(controller.didStartTracking)
        return minimized.count
    }

    /// Restore the windows the last swipe down minimized. Returns how many.
    @discardableResult
    public func restore() -> Int {
        pruneStale()
        let windows = remembered
        remembered.removeAll()
        var restored = 0
        for window in windows.reversed() {
            controller.didStopTracking(window)
            if controller.state(of: window) == .minimized, controller.setMinimized(window, false) {
                restored += 1
            }
        }
        return restored
    }

    /// Drop one window, e.g. because the user restored it from the Dock.
    public func forget(_ window: Window) {
        forget { $0 == window }
    }

    /// Drop every window matching a predicate, e.g. all windows of a quit app.
    public func forget(where shouldForget: (Window) -> Bool) {
        let dropped = remembered.filter(shouldForget)
        guard !dropped.isEmpty else { return }
        remembered.removeAll(where: shouldForget)
        dropped.forEach(controller.didStopTracking)
    }

    /// Drop windows that are no longer minimized or no longer exist.
    public func pruneStale() {
        forget { controller.state(of: $0) != .minimized }
    }
}
