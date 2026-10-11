/// One frame of touch input, already reduced to what the recognizer needs.
///
/// Coordinates are normalized to the trackpad surface (0...1). `y` grows toward
/// the top of the trackpad (away from the user), matching MultitouchSupport.
public struct TouchFrame: Equatable, Sendable {
    public var fingerCount: Int
    public var x: Float
    public var y: Float
    public var timestamp: Double

    public init(fingerCount: Int, x: Float, y: Float, timestamp: Double) {
        self.fingerCount = fingerCount
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }
}

public enum SwipeGesture: Equatable, Sendable {
    /// Fingers moved toward the user (y decreased).
    case swipeDown
    /// Fingers moved away from the user (y increased).
    case swipeUp
}

public struct SwipeRecognizerConfiguration: Equatable, Sendable {
    /// Minimum vertical travel, as a fraction of trackpad height.
    public var threshold: Float
    /// Vertical travel must exceed horizontal travel times this ratio.
    public var dominanceRatio: Float
    /// Travel is measured over at most this many seconds. Movement slower than
    /// `threshold / window` never fires, which filters out resting-hand drift.
    public var window: Double
    /// A gap this long between frames means we missed a lift; start over.
    public var maxFrameGap: Double

    public static let defaultThreshold: Float = 0.18
    public static let thresholdRange: ClosedRange<Float> = 0.08...0.40

    public init(
        threshold: Float = SwipeRecognizerConfiguration.defaultThreshold,
        dominanceRatio: Float = 1.5,
        window: Double = 0.6,
        maxFrameGap: Double = 0.25
    ) {
        self.threshold = threshold
        self.dominanceRatio = dominanceRatio
        self.window = window
        self.maxFrameGap = maxFrameGap
    }
}

/// Turns a stream of `TouchFrame`s into at most one `SwipeGesture` per gesture.
///
/// Rules:
/// - Only exactly-3-finger contact is tracked.
/// - Fires once per gesture when vertical travel within `window` reaches
///   `threshold` and is greater than `dominanceRatio` × horizontal travel.
/// - Any change in finger count restarts tracking; lifting all fingers ends
///   the gesture.
/// - A gesture that ever reaches 4+ fingers is ignored until all fingers lift,
///   so dropping from 4 to 3 fingers mid-gesture cannot trigger a swipe.
///
/// Pure value type with no clock or threading of its own; safe to unit test.
public struct SwipeRecognizer: Sendable {
    public var configuration: SwipeRecognizerConfiguration

    private struct Sample: Sendable {
        var x: Float
        var y: Float
        var t: Double
    }

    private var samples: [Sample] = []
    private var lastFingerCount = 0
    private var lastTimestamp: Double?
    private var fired = false
    private var tainted = false

    public init(configuration: SwipeRecognizerConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func process(_ frame: TouchFrame) -> SwipeGesture? {
        if let last = lastTimestamp, frame.timestamp - last > configuration.maxFrameGap {
            reset()
        }
        lastTimestamp = frame.timestamp

        if frame.fingerCount <= 0 {
            reset()
            return nil
        }
        if frame.fingerCount >= 4 {
            tainted = true
        }
        if frame.fingerCount != lastFingerCount {
            samples.removeAll(keepingCapacity: true)
            fired = false
            lastFingerCount = frame.fingerCount
        }
        guard frame.fingerCount == 3, !tainted, !fired else { return nil }

        samples.append(Sample(x: frame.x, y: frame.y, t: frame.timestamp))
        while let first = samples.first, frame.timestamp - first.t > configuration.window {
            samples.removeFirst()
        }
        guard let anchor = samples.first else { return nil }

        let dx = frame.x - anchor.x
        let dy = frame.y - anchor.y
        guard abs(dy) >= configuration.threshold,
              abs(dy) > configuration.dominanceRatio * abs(dx) else { return nil }

        fired = true
        return dy < 0 ? .swipeDown : .swipeUp
    }

    /// Forget the current gesture entirely (as if all fingers lifted).
    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        lastFingerCount = 0
        lastTimestamp = nil
        fired = false
        tainted = false
    }
}
