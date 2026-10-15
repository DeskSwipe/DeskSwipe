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

/// Remembers exactly which windows each "show desktop" minimized so that
/// "restore" brings back only those.
///
/// - Each swipe down that minimizes something is remembered as its own
///   group. Restore brings back the most recent group only; restoring again
///   brings back the group before it. Groups are never overwritten, and a
///   swipe down that minimizes nothing leaves them untouched.
/// - Windows that were restored by other means, or whose app quit, are
///   dropped quietly (via `forget`, or lazily on the next action).
/// - Windows the user minimized themselves are never remembered, so restore
///   never touches them.
public final class ShowDesktopController<Controller: WindowControlling> {
    public typealias Window = Controller.Window

    private let controller: Controller

    /// One group per swipe down, oldest first. Within a group windows are
    /// frontmost first; restore walks a group back to front so the window
    /// that was in front ends up in front again.
    public private(set) var groups: [[Window]] = []

    /// Every remembered window, newest group first.
    public var remembered: [Window] { groups.reversed().flatMap { $0 } }

    public init(controller: Controller) {
        self.controller = controller
    }

    /// Minimize every visible window. Returns how many were minimized now.
    @discardableResult
    public func showDesktop() -> Int {
        pruneStale()
        var group: [Window] = []
        var seen = Set(groups.joined())
        for window in controller.currentWindows() where !seen.contains(window) {
            guard controller.state(of: window) == .visible,
                  controller.setMinimized(window, true) else { continue }
            group.append(window)
            seen.insert(window)
        }
        guard !group.isEmpty else { return 0 }
        groups.append(group)
        group.forEach(controller.didStartTracking)
        return group.count
    }

    /// Restore the most recent group this controller minimized. Returns how
    /// many windows came back.
    @discardableResult
    public func restore() -> Int {
        pruneStale()
        guard let group = groups.popLast() else { return 0 }
        var restored = 0
        for window in group.reversed() {
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
        var dropped: [Window] = []
        for index in groups.indices {
            dropped += groups[index].filter(shouldForget)
            groups[index].removeAll(where: shouldForget)
        }
        guard !dropped.isEmpty else { return }
        groups.removeAll(where: \.isEmpty)
        dropped.forEach(controller.didStopTracking)
    }

    /// Drop windows that are no longer minimized or no longer exist.
    public func pruneStale() {
        forget { controller.state(of: $0) != .minimized }
    }
}
