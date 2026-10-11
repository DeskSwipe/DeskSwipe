import Testing
@testable import DeskSwipeCore

/// In-memory stand-in for the Accessibility API.
private final class FakeWindows: WindowControlling {
    typealias Window = String

    var order: [String] = []
    var states: [String: WindowState] = [:]
    var refuseChanges: Set<String> = []
    private(set) var minimizeLog: [(String, Bool)] = []
    private(set) var tracked: Set<String> = []

    init(_ windows: [(String, WindowState)]) {
        for (name, state) in windows {
            order.append(name)
            states[name] = state
        }
    }

    func currentWindows() -> [String] {
        order.filter { states[$0] != .gone }
    }

    func state(of window: String) -> WindowState {
        states[window] ?? .gone
    }

    func setMinimized(_ window: String, _ minimized: Bool) -> Bool {
        guard let state = states[window], state != .gone, state != .ignored,
              !refuseChanges.contains(window) else { return false }
        states[window] = minimized ? .minimized : .visible
        minimizeLog.append((window, minimized))
        return true
    }

    func didStartTracking(_ window: String) { tracked.insert(window) }
    func didStopTracking(_ window: String) { tracked.remove(window) }

    var restoredOrder: [String] { minimizeLog.filter { !$0.1 }.map(\.0) }
}

@Suite("ShowDesktopController")
struct ShowDesktopControllerTests {
    @Test func minimizesOnlyVisibleWindows() {
        let fake = FakeWindows([("a", .visible), ("b", .minimized), ("full", .ignored), ("c", .visible)])
        let controller = ShowDesktopController(controller: fake)

        #expect(controller.showDesktop() == 2)
        #expect(controller.remembered == ["a", "c"])
        #expect(fake.states["full"] == .ignored)
        #expect(fake.tracked == ["a", "c"])
    }

    @Test func restoreLeavesUserMinimizedWindowsAlone() {
        let fake = FakeWindows([("a", .visible), ("mine", .minimized)])
        let controller = ShowDesktopController(controller: fake)

        controller.showDesktop()
        #expect(controller.restore() == 1)
        #expect(fake.states["a"] == .visible)
        #expect(fake.states["mine"] == .minimized)
        #expect(controller.remembered.isEmpty)
        #expect(fake.tracked.isEmpty)
    }

    @Test func secondSwipeDownMergesInsteadOfOverwriting() {
        let fake = FakeWindows([("a", .visible), ("b", .visible)])
        let controller = ShowDesktopController(controller: fake)

        controller.showDesktop()
        // Nothing visible now: the list must survive.
        #expect(controller.showDesktop() == 0)
        #expect(controller.remembered == ["a", "b"])

        // User opens a new window, swipes down again: merged, newest in front.
        fake.order.insert("new", at: 0)
        fake.states["new"] = .visible
        #expect(controller.showDesktop() == 1)
        #expect(controller.remembered == ["new", "a", "b"])

        #expect(controller.restore() == 3)
        // Back to front, so the newest window ends up in front.
        #expect(fake.restoredOrder == ["b", "a", "new"])
    }

    @Test func manuallyRestoredWindowIsDroppedAndNotTouched() {
        let fake = FakeWindows([("a", .visible), ("b", .visible)])
        let controller = ShowDesktopController(controller: fake)
        controller.showDesktop()

        // User clicks the Dock thumbnail for "a"; the platform layer reports it.
        fake.states["a"] = .visible
        controller.forget("a")
        #expect(controller.remembered == ["b"])
        #expect(!fake.tracked.contains("a"))

        // Later the user minimizes "a" themselves: restore must not touch it.
        fake.states["a"] = .minimized
        controller.restore()
        #expect(fake.states["a"] == .minimized)
        #expect(fake.states["b"] == .visible)
    }

    @Test func manuallyRestoredWindowIsPrunedLazily() {
        // Even without a notification, a restored window drops out on the next swipe.
        let fake = FakeWindows([("a", .visible), ("b", .visible)])
        let controller = ShowDesktopController(controller: fake)
        controller.showDesktop()

        fake.states["a"] = .visible
        controller.showDesktop()
        #expect(controller.remembered == ["a", "b"])
        #expect(fake.minimizeLog.filter { $0.0 == "a" && $0.1 }.count == 2)
    }

    @Test func quitAppWindowsAreDroppedWithoutCrashing() {
        let fake = FakeWindows([("app1.w1", .visible), ("app1.w2", .visible), ("app2.w1", .visible)])
        let controller = ShowDesktopController(controller: fake)
        controller.showDesktop()

        // app1 quits: its windows become stale references.
        fake.states["app1.w1"] = nil
        fake.states["app1.w2"] = nil
        controller.forget { $0.hasPrefix("app1.") }
        #expect(controller.remembered == ["app2.w1"])

        #expect(controller.restore() == 1)
    }

    @Test func staleReferencesAreSkippedOnRestore() {
        // App vanished without any notification reaching us.
        let fake = FakeWindows([("a", .visible), ("b", .visible)])
        let controller = ShowDesktopController(controller: fake)
        controller.showDesktop()

        fake.states["a"] = .gone
        #expect(controller.restore() == 1)
        #expect(fake.restoredOrder == ["b"])
    }

    @Test func windowsThatRefuseToMinimizeAreNotRemembered() {
        let fake = FakeWindows([("a", .visible), ("stubborn", .visible)])
        fake.refuseChanges = ["stubborn"]
        let controller = ShowDesktopController(controller: fake)

        #expect(controller.showDesktop() == 1)
        #expect(controller.remembered == ["a"])
    }

    @Test func restoreWithNothingRememberedIsANoOp() {
        let fake = FakeWindows([("mine", .minimized)])
        let controller = ShowDesktopController(controller: fake)
        #expect(controller.restore() == 0)
        #expect(fake.states["mine"] == .minimized)
    }

    @Test func forgettingUnknownWindowIsHarmless() {
        let fake = FakeWindows([("a", .visible)])
        let controller = ShowDesktopController(controller: fake)
        controller.showDesktop()
        controller.forget("nope")
        #expect(controller.remembered == ["a"])
    }
}
