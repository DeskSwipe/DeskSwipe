import AppKit
import DeskSwipeCore
import IOKit
import os

private let log = Logger(subsystem: "DeskSwipe", category: "Multitouch")

// MARK: - Private framework bindings

private typealias MTDeviceRef = UnsafeMutableRawPointer
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?,                   // device
    UnsafeMutableRawPointer?,       // MTTouch array
    Int32,                          // number of touches
    Double,                         // timestamp
    Int32                           // frame
) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterContactFrameCallbackFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTUnregisterContactFrameCallbackFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef) -> Void

private struct MultitouchSymbols {
    let createList: MTDeviceCreateListFn
    let registerCallback: MTRegisterContactFrameCallbackFn
    let start: MTDeviceStartFn
    // Optional: used for clean teardown when re-enumerating.
    let unregisterCallback: MTUnregisterContactFrameCallbackFn?
    let stop: MTDeviceStopFn?

    static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    static func load() -> Result<MultitouchSymbols, MultitouchService.Failure> {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            return .failure(.frameworkUnavailable(reason))
        }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let createList = symbol("MTDeviceCreateList", as: MTDeviceCreateListFn.self),
              let register = symbol("MTRegisterContactFrameCallback", as: MTRegisterContactFrameCallbackFn.self),
              let start = symbol("MTDeviceStart", as: MTDeviceStartFn.self)
        else {
            return .failure(.symbolsMissing)
        }
        return .success(MultitouchSymbols(
            createList: createList,
            registerCallback: register,
            start: start,
            unregisterCallback: symbol("MTUnregisterContactFrameCallback", as: MTUnregisterContactFrameCallbackFn.self),
            stop: symbol("MTDeviceStop", as: MTDeviceStopFn.self)
        ))
    }
}

// MARK: - Gesture routing (called on the framework's own thread)

/// Owns one recognizer per device. Thread-safe: the framework invokes the
/// contact callback on its own thread, while settings change on main.
final class GestureRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizers: [UInt: SwipeRecognizer] = [:]
    private var configuration = SwipeRecognizerConfiguration()
    private var enabled = true

    /// Delivered on the main queue.
    var onGesture: ((SwipeGesture) -> Void)?

    func update(configuration: SwipeRecognizerConfiguration, enabled: Bool) {
        lock.lock()
        self.configuration = configuration
        self.enabled = enabled
        for key in recognizers.keys {
            recognizers[key]?.configuration = configuration
            if !enabled { recognizers[key]?.reset() }
        }
        lock.unlock()
    }

    func reset() {
        lock.lock()
        recognizers.removeAll()
        lock.unlock()
    }

    func handle(device: UInt, frame: TouchFrame) {
        lock.lock()
        guard enabled else {
            lock.unlock()
            return
        }
        var recognizer = recognizers[device] ?? SwipeRecognizer(configuration: configuration)
        let gesture = recognizer.process(frame)
        recognizers[device] = recognizer
        lock.unlock()

        if let gesture {
            DispatchQueue.main.async { [weak self] in self?.onGesture?(gesture) }
        }
    }
}

/// The C callback cannot capture context, so it reaches the router through
/// this global. Set once before any device is started.
private let sharedRouter = GestureRouter()

private let contactCallback: MTContactCallback = { device, touches, count, timestamp, _ in
    let buffer: UnsafeBufferPointer<MTTouch>
    if let touches, count > 0 {
        buffer = UnsafeBufferPointer(start: touches.assumingMemoryBound(to: MTTouch.self), count: Int(count))
    } else {
        buffer = UnsafeBufferPointer(start: nil, count: 0)
    }
    let frame = TouchFrame(touches: buffer, timestamp: timestamp)
    sharedRouter.handle(device: UInt(bitPattern: device), frame: frame)
    return 0
}

// MARK: - Device management

/// Starts every multitouch device, routes frames to `GestureRouter`, and
/// re-enumerates devices when trackpads are connected/disconnected or the
/// Mac wakes from sleep.
final class MultitouchService {
    enum Failure: Error, CustomStringConvertible {
        case layoutMismatch
        case frameworkUnavailable(String)
        case symbolsMissing

        var description: String {
            switch self {
            case .layoutMismatch:
                return "MTTouch layout is not 96 bytes; gesture input disabled"
            case .frameworkUnavailable(let reason):
                return "MultitouchSupport could not be loaded (\(reason))"
            case .symbolsMissing:
                return "MultitouchSupport is missing required functions"
            }
        }
    }

    var router: GestureRouter { sharedRouter }

    /// Called on main whenever the set of running devices changes.
    var onDevicesChanged: ((Int) -> Void)?

    private(set) var failure: Failure?
    private(set) var deviceCount = 0

    private var symbols: MultitouchSymbols?
    private var deviceList: CFArray?
    private var notificationPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0
    private var terminateIterator: io_iterator_t = 0
    private var pendingRestart: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        guard MTTouch.layoutIsValid else {
            failure = .layoutMismatch
            log.error("\(Failure.layoutMismatch.description, privacy: .public)")
            return
        }
        switch MultitouchSymbols.load() {
        case .success(let loaded):
            symbols = loaded
        case .failure(let error):
            failure = error
            log.error("\(error.description, privacy: .public)")
            return
        }
        startDevices()
        watchForHotPlug()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleRestart(reason: "wake")
        }
    }

    deinit {
        stopDevices()
        if matchIterator != 0 { IOObjectRelease(matchIterator) }
        if terminateIterator != 0 { IOObjectRelease(terminateIterator) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private var devices: [MTDeviceRef] {
        guard let deviceList else { return [] }
        return (0..<CFArrayGetCount(deviceList)).compactMap {
            CFArrayGetValueAtIndex(deviceList, $0).map { UnsafeMutableRawPointer(mutating: $0) }
        }
    }

    private func startDevices() {
        guard let symbols else { return }
        deviceList = symbols.createList()?.takeRetainedValue()
        for device in devices {
            symbols.registerCallback(device, contactCallback)
            symbols.start(device, 0)
        }
        deviceCount = devices.count
        log.info("Started \(self.deviceCount) multitouch device(s)")
        onDevicesChanged?(deviceCount)
    }

    private func stopDevices() {
        guard let symbols else { return }
        for device in devices {
            symbols.unregisterCallback?(device, contactCallback)
            symbols.stop?(device)
        }
        deviceList = nil
        deviceCount = 0
        sharedRouter.reset()
    }

    /// Debounced: hot-plug sends bursts of notifications, and a freshly
    /// connected trackpad needs a moment before it can be started.
    fileprivate func scheduleRestart(reason: String) {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            log.info("Re-enumerating multitouch devices (\(reason, privacy: .public))")
            self.stopDevices()
            self.startDevices()
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func watchForHotPlug() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            // Drain the iterator to re-arm the notification.
            var drained = 0
            while case let service = IOIteratorNext(iterator), service != 0 {
                IOObjectRelease(service)
                drained += 1
            }
            guard let refcon, drained > 0 else { return }
            let service = Unmanaged<MultitouchService>.fromOpaque(refcon).takeUnretainedValue()
            service.scheduleRestart(reason: "device change")
        }

        for (type, iterator) in [
            (kIOFirstMatchNotification, \MultitouchService.matchIterator),
            (kIOTerminatedNotification, \MultitouchService.terminateIterator),
        ] {
            var it: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), callback, refcon, &it
            )
            guard result == KERN_SUCCESS else {
                log.error("IOServiceAddMatchingNotification failed: \(result)")
                continue
            }
            // Existing devices are already started; just arm the iterator.
            while case let service = IOIteratorNext(it), service != 0 { IOObjectRelease(service) }
            self[keyPath: iterator] = it
        }
    }
}
