/// One frame of touch input, already reduced to what the recognizer needs.
///
/// Coordinates are normalized to the trackpad surface (0...1). `y` grows toward
/// the top of the trackpad (away from the user), matching MultitouchSupport.
public struct TouchFrame: Equatable, Sendable {
    /// One finger on the surface. `id` stays the same for as long as that
    /// finger stays down.
    public struct Finger: Equatable, Sendable {
        public var id: Int32
        public var x: Float
        public var y: Float

        public init(id: Int32, x: Float, y: Float) {
            self.id = id
            self.x = x
            self.y = y
        }
    }

    public var fingerCount: Int
    /// Average position of `fingers`.
    public var x: Float
    public var y: Float
    public var timestamp: Double
    public var fingers: [Finger]

    public init(fingers: [Finger], timestamp: Double) {
        let n = Float(max(fingers.count, 1))
        self.fingerCount = fingers.count
        self.x = fingers.reduce(0) { $0 + $1.x } / n
        self.y = fingers.reduce(0) { $0 + $1.y } / n
        self.timestamp = timestamp
        self.fingers = fingers
    }

    /// `fingerCount` fingers moving together at (`x`, `y`).
    public init(fingerCount: Int, x: Float, y: Float, timestamp: Double) {
        self.init(
            fingers: (0..<max(fingerCount, 0)).map { Finger(id: Int32($0), x: x, y: y) },
            timestamp: timestamp
        )
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
    /// Each finger must travel at least this fraction of `threshold` in the
    /// swipe's direction, so two moving fingers plus a resting thumb or palm
    /// don't count as a 3-finger swipe.
    public var perFingerRatio: Float
    /// If any finger moves this far (fraction of trackpad height or width)
    /// before the third finger lands, the gesture is a scroll in progress and
    /// is ignored until all fingers lift.
    public var preSwipeMovementLimit: Float

    public static let defaultThreshold: Float = 0.18
    public static let thresholdRange: ClosedRange<Float> = 0.08...0.40

    public init(
        threshold: Float = SwipeRecognizerConfiguration.defaultThreshold,
        dominanceRatio: Float = 1.5,
        window: Double = 0.6,
        maxFrameGap: Double = 0.25,
        perFingerRatio: Float = 0.5,
        preSwipeMovementLimit: Float = 0.03
    ) {
        self.threshold = threshold
        self.dominanceRatio = dominanceRatio
        self.window = window
        self.maxFrameGap = maxFrameGap
        self.perFingerRatio = perFingerRatio
        self.preSwipeMovementLimit = preSwipeMovementLimit
    }
}

/// Turns a stream of `TouchFrame`s into at most one `SwipeGesture` per gesture.
///
/// Rules:
/// - Only exactly-3-finger contact is tracked.
/// - Fires once per gesture when vertical travel within `window` reaches
///   `threshold` and is greater than `dominanceRatio` × horizontal travel,
///   and every one of the three fingers moved that way by at least
///   `perFingerRatio` × `threshold`.
/// - Any change in finger count restarts tracking; lifting all fingers ends
///   the gesture.
/// - A gesture that ever reaches 4+ fingers is ignored until all fingers lift,
///   so dropping from 4 to 3 fingers mid-gesture cannot trigger a swipe.
/// - A gesture where fingers were already moving before the third one landed
///   (a two-finger scroll that picks up a thumb or palm) is ignored the same way.
///
/// Pure value type with no clock or threading of its own; safe to unit test.
public struct SwipeRecognizer: Sendable {
    public var configuration: SwipeRecognizerConfiguration

    private struct Sample: Sendable {
        var x: Float
        var y: Float
        var t: Double
        var fingers: [TouchFrame.Finger]
    }

    private var samples: [Sample] = []
    private var lastFingerCount = 0
    private var lastTimestamp: Double?
    private var fired = false
    private var tainted = false
    /// Where each finger first touched, while fewer than 3 were down.
    private var landingPositions: [Int32: (x: Float, y: Float)] = [:]
    private var reachedThree = false

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
        if frame.fingerCount >= 3 {
            reachedThree = true
        } else if !reachedThree, !tainted, movedBeforeThirdFinger(frame) {
            tainted = true
        }
        if frame.fingerCount != lastFingerCount {
            samples.removeAll(keepingCapacity: true)
            fired = false
            lastFingerCount = frame.fingerCount
        }
        guard frame.fingerCount == 3, !tainted, !fired else { return nil }

        samples.append(Sample(x: frame.x, y: frame.y, t: frame.timestamp, fingers: frame.fingers))
        while let first = samples.first, frame.timestamp - first.t > configuration.window {
            samples.removeFirst()
        }
        guard let anchor = samples.first else { return nil }

        let dx = frame.x - anchor.x
        let dy = frame.y - anchor.y
        guard abs(dy) >= configuration.threshold,
              abs(dy) > configuration.dominanceRatio * abs(dx),
              everyFingerFollowed(dy: dy, from: anchor, to: frame) else { return nil }

        fired = true
        return dy < 0 ? .swipeDown : .swipeUp
    }

    /// Records where fingers land and reports whether any has moved further
    /// than `preSwipeMovementLimit` since, while fewer than 3 are down.
    private mutating func movedBeforeThirdFinger(_ frame: TouchFrame) -> Bool {
        let limit = configuration.preSwipeMovementLimit
        for finger in frame.fingers {
            guard let origin = landingPositions[finger.id] else {
                landingPositions[finger.id] = (finger.x, finger.y)
                continue
            }
            if abs(finger.x - origin.x) > limit || abs(finger.y - origin.y) > limit {
                return true
            }
        }
        return false
    }

    /// True when each finger in `frame` moved in the direction of `dy` by at
    /// least `perFingerRatio` × `threshold` since `anchor`. A finger missing
    /// from `anchor` counts as not following.
    private func everyFingerFollowed(dy: Float, from anchor: Sample, to frame: TouchFrame) -> Bool {
        let minimum = configuration.perFingerRatio * configuration.threshold
        return frame.fingers.allSatisfy { finger in
            guard let start = anchor.fingers.first(where: { $0.id == finger.id }) else { return false }
            let travel = finger.y - start.y
            return travel * dy > 0 && abs(travel) >= minimum
        }
    }

    /// Forget the current gesture entirely (as if all fingers lifted).
    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        lastFingerCount = 0
        lastTimestamp = nil
        fired = false
        tainted = false
        landingPositions.removeAll(keepingCapacity: true)
        reachedThree = false
    }
}
