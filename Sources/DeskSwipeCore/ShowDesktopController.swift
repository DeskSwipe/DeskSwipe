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

/// Remembers exactly which windows a "show desktop" minimized so that
/// "restore" brings back only those.
///
/// - Swipe down merges into the remembered list; it never replaces it.
/// - Windows that were restored by other means, or whose app quit, are
///   dropped quietly (via `forget`, or lazily on the next action).
/// - Windows the user minimized themselves are never remembered, so restore
///   never touches them.
public final class ShowDesktopController<Controller: WindowControlling> {
    public typealias Window = Controller.Window

    private let controller: Controller

    /// Frontmost first. Restore walks it back to front so the window that
    /// was in front ends up in front again.
    public private(set) var remembered: [Window] = []

    public init(controller: Controller) {
        self.controller = controller
    }

    /// Minimize every visible window. Returns how many were minimized now.
    @discardableResult
    public func showDesktop() -> Int {
        pruneStale()
        var batch: [Window] = []
        var seen = Set(remembered)
        for window in controller.currentWindows() where !seen.contains(window) {
            guard controller.state(of: window) == .visible,
                  controller.setMinimized(window, true) else { continue }
            batch.append(window)
            seen.insert(window)
        }
        // The newest batch was in front of anything minimized earlier.
        remembered = batch + remembered
        batch.forEach(controller.didStartTracking)
        return batch.count
    }

    /// Restore the windows this controller minimized. Returns how many.
    @discardableResult
    public func restore() -> Int {
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
        guard let index = remembered.firstIndex(of: window) else { return }
        remembered.remove(at: index)
        controller.didStopTracking(window)
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
