import Testing
@testable import DeskSwipeCore

@Suite("GestureConflict")
struct GestureConflictTests {
    @Test func threeFingerVerticalSwipeOnIsAConflict() {
        let conflicts = GestureConflict.detect(
            trackpads: [.init(threeFingerVerticalSwipe: 2, threeFingerDrag: false)],
            dock: .init()
        )
        #expect(conflicts == [.systemThreeFingerSwipe])
    }

    @Test func fourFingerSetupHasNoConflict() {
        let conflicts = GestureConflict.detect(
            trackpads: [.init(threeFingerVerticalSwipe: 0), .init(threeFingerVerticalSwipe: 0)],
            dock: .init(missionControl: true, appExpose: true)
        )
        #expect(conflicts.isEmpty)
    }

    @Test func missingKeysAssumeMacOSDefault() {
        let conflicts = GestureConflict.detect(trackpads: [.init(), .init()], dock: .init())
        #expect(conflicts == [.systemThreeFingerSwipe])
    }

    @Test func emptyBluetoothDomainDoesNotOverrideBuiltIn() {
        let conflicts = GestureConflict.detect(
            trackpads: [.init(threeFingerVerticalSwipe: 0), .init()],
            dock: .init()
        )
        #expect(conflicts.isEmpty)
    }

    @Test func dockGesturesOffMeansNoConflict() {
        let conflicts = GestureConflict.detect(
            trackpads: [.init(threeFingerVerticalSwipe: 2)],
            dock: .init(missionControl: false, appExpose: false)
        )
        #expect(conflicts.isEmpty)
    }

    @Test func threeFingerDragIsReported() {
        let conflicts = GestureConflict.detect(
            trackpads: [.init(threeFingerVerticalSwipe: 0, threeFingerDrag: true)],
            dock: .init()
        )
        #expect(conflicts == [.threeFingerDrag])
    }

    @Test func invertSwapsDirections() {
        #expect(SwipeGesture.swipeDown.inverted == .swipeUp)
        #expect(SwipeGesture.swipeUp.inverted == .swipeDown)
    }
}
