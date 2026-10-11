// swift-tools-version:5.10
import PackageDescription
import Foundation

// The Swift Testing macro plugin ships with the Command Line Tools, but the
// CLT build of SwiftPM does not always pass its search path to every compile
// step. Add it explicitly when it exists; with full Xcode this is a no-op.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: cltTestingPlugins)
        ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])]
        : []

let package = Package(
    name: "DeskSwipe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeskSwipe", targets: ["DeskSwipe"]),
    ],
    targets: [
        // Pure, platform-light logic: gesture recognition, touch layout,
        // bookkeeping of which windows we minimized. Fully unit tested.
        .target(name: "DeskSwipeCore"),

        // The menu bar app: multitouch plumbing, Accessibility, UI.
        .executableTarget(
            name: "DeskSwipe",
            dependencies: ["DeskSwipeCore"]
        ),

        .testTarget(
            name: "DeskSwipeCoreTests",
            dependencies: ["DeskSwipeCore"],
            swiftSettings: testSwiftSettings
        ),
    ]
)
