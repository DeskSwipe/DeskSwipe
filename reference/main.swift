// main.swift
// Windows-style "show desktop" for macOS:
//   3-finger swipe DOWN -> minimize all windows (remembers which ones it minimized)
//   3-finger swipe UP   -> restore only those windows
//
// Build:  swiftc -O main.swift -o showdesktop
// Run:    ./showdesktop
// Needs:  Accessibility permission for the app that launches it (Terminal at first).

import Cocoa
import ApplicationServices

// MARK: - Private MultitouchSupport framework, loaded at runtime

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?,   // device
    UnsafeMutableRawPointer?,   // touches array
    Int32,                      // number of touches
    Double,                     // timestamp
    Int32                       // frame
) -> Int32

typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>
typealias RegisterFn   = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
typealias StartFn      = @convention(c) (MTDeviceRef, Int32) -> Void

guard let mtHandle = dlopen(
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
    RTLD_NOW
) else {
    fatalError("Could not load MultitouchSupport")
}

func loadSymbol<T>(_ name: String, as type: T.Type) -> T {
    guard let p = dlsym(mtHandle, name) else { fatalError("Missing symbol \(name)") }
    return unsafeBitCast(p, to: type)
}

let MTDeviceCreateList            = loadSymbol("MTDeviceCreateList", as: CreateListFn.self)
let MTRegisterContactFrameCallback = loadSymbol("MTRegisterContactFrameCallback", as: RegisterFn.self)
let MTDeviceStart                 = loadSymbol("MTDeviceStart", as: StartFn.self)

// MARK: - Window control through the Accessibility API

var minimizedByUs: [AXUIElement] = []

func windows(of app: NSRunningApplication) -> [AXUIElement] {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
          let list = ref as? [AXUIElement] else { return [] }
    return list
}

func isMinimized(_ window: AXUIElement) -> Bool {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref)
    return (ref as? Bool) ?? false
}

func setMinimized(_ window: AXUIElement, _ value: Bool) {
    AXUIElementSetAttributeValue(
        window,
        kAXMinimizedAttribute as CFString,
        value ? kCFBooleanTrue : kCFBooleanFalse
    )
}

func minimizeAll() {
    let myPID = ProcessInfo.processInfo.processIdentifier
    for app in NSWorkspace.shared.runningApplications
    where app.activationPolicy == .regular && app.processIdentifier != myPID {
        for w in windows(of: app) where !isMinimized(w) {
            setMinimized(w, true)
            minimizedByUs.append(w)
        }
    }
}

func restoreAll() {
    for w in minimizedByUs { setMinimized(w, false) }
    minimizedByUs.removeAll()
}

// MARK: - Gesture detection

var tracking = false
var fired = false
var startX: Float = 0
var startY: Float = 0

let swipeThreshold: Float = 0.18   // fraction of trackpad height (0...1)

let contactCallback: MTContactCallback = { _, data, count, _, _ in
    guard let data = data else { return 0 }

    if count == 3 {
        // Each MTTouch is 96 bytes; normalized position x,y floats sit at offsets 32 and 36.
        var sumX: Float = 0, sumY: Float = 0
        for i in 0..<3 {
            let base = i * 96
            sumX += data.load(fromByteOffset: base + 32, as: Float.self)
            sumY += data.load(fromByteOffset: base + 36, as: Float.self)
        }
        let avgX = sumX / 3, avgY = sumY / 3

        if !tracking {
            tracking = true
            fired = false
            startX = avgX
            startY = avgY
        } else if !fired {
            let dx = avgX - startX
            let dy = avgY - startY          // y grows toward the top of the trackpad
            if abs(dy) > swipeThreshold && abs(dy) > abs(dx) * 1.5 {
                fired = true
                DispatchQueue.main.async {
                    if dy < 0 { minimizeAll() } else { restoreAll() }
                }
            }
        }
    } else if count > 3 {
        fired = true                         // 4+ fingers: not our gesture
    } else {
        tracking = false                     // fewer than 3 fingers: reset
    }
    return 0
}

// MARK: - Start

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(options) {
    print("Grant Accessibility permission in System Settings > Privacy & Security, then run again.")
}

let devices = MTDeviceCreateList().takeRetainedValue() as [AnyObject]
for d in devices {
    let device = Unmanaged.passUnretained(d).toOpaque()
    MTRegisterContactFrameCallback(device, contactCallback)
    MTDeviceStart(device, 0)
}

print("Running. 3-finger swipe down = minimize all, up = restore. Ctrl+C to quit.")
RunLoop.main.run()
