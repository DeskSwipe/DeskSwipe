import Testing
@testable import DeskSwipeCore

@Test func coreModuleLoads() {
    #expect(!DeskSwipeCore.version.isEmpty)
}
