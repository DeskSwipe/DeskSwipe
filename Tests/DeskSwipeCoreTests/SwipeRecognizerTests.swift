import Testing
@testable import DeskSwipeCore

// MARK: - Synthetic frame helpers

/// Frames sampled at ~100 Hz, like a real trackpad.
private let frameInterval = 0.01

/// A straight-line move with a constant finger count, inclusive of both ends.
private func move(
    fingers: Int = 3,
    from start: (x: Float, y: Float),
    to end: (x: Float, y: Float),
    duration: Double,
    startTime: Double = 0
) -> [TouchFrame] {
    let steps = max(1, Int((duration / frameInterval).rounded()))
    return (0...steps).map { i in
        let f = Float(i) / Float(steps)
        return TouchFrame(
            fingerCount: fingers,
            x: start.x + (end.x - start.x) * f,
            y: start.y + (end.y - start.y) * f,
            timestamp: startTime + Double(i) * frameInterval
        )
    }
}

/// Fingers landing one by one, as they do on real hardware.
private func land(upTo fingers: Int = 3, at p: (x: Float, y: Float), startTime: Double) -> [TouchFrame] {
    (1..<fingers).map { n in
        TouchFrame(fingerCount: n, x: p.x, y: p.y, timestamp: startTime + Double(n - 1) * frameInterval)
    }
}

private func lift(at time: Double) -> TouchFrame {
    TouchFrame(fingerCount: 0, x: 0, y: 0, timestamp: time)
}

private func recognize(_ frames: [TouchFrame], configuration: SwipeRecognizerConfiguration = .init()) -> [SwipeGesture] {
    var recognizer = SwipeRecognizer(configuration: configuration)
    return frames.compactMap { recognizer.process($0) }
}

/// A complete, realistic 3-finger gesture: land, move, lift.
private func gesture(
    fingers: Int = 3,
    from start: (x: Float, y: Float),
    to end: (x: Float, y: Float),
    duration: Double = 0.2,
    startTime: Double = 0
) -> [TouchFrame] {
    let landing = land(upTo: fingers, at: start, startTime: startTime)
    let moveStart = startTime + Double(landing.count) * frameInterval
    let moving = move(fingers: fingers, from: start, to: end, duration: duration, startTime: moveStart)
    return landing + moving + [lift(at: moving.last!.timestamp + frameInterval)]
}

// MARK: - Required scenarios

@Suite("SwipeRecognizer")
struct SwipeRecognizerTests {
    @Test func cleanSwipeDown() {
        let frames = gesture(from: (0.5, 0.7), to: (0.52, 0.3))
        #expect(recognize(frames) == [.swipeDown])
    }

    @Test func cleanSwipeUp() {
        let frames = gesture(from: (0.5, 0.3), to: (0.48, 0.7))
        #expect(recognize(frames) == [.swipeUp])
    }

    @Test func diagonalSwipeIsIgnored() {
        // 0.3 vertical vs 0.3 horizontal: not 1.5x dominant.
        let frames = gesture(from: (0.2, 0.7), to: (0.5, 0.4))
        #expect(recognize(frames).isEmpty)
    }

    @Test func fourFingerSwipeIsIgnored() {
        let frames = gesture(fingers: 4, from: (0.5, 0.7), to: (0.5, 0.2))
        #expect(recognize(frames).isEmpty)
    }

    @Test func slowDriftIsIgnored() {
        // 0.4 of vertical travel spread over 5 seconds.
        let frames = gesture(from: (0.5, 0.8), to: (0.5, 0.4), duration: 5)
        #expect(recognize(frames).isEmpty)
    }

    @Test func twoSwipesInARow() {
        let down = gesture(from: (0.5, 0.7), to: (0.5, 0.3))
        let up = gesture(from: (0.5, 0.3), to: (0.5, 0.7), startTime: down.last!.timestamp + 0.1)
        #expect(recognize(down + up) == [.swipeDown, .swipeUp])
    }

    // MARK: - Further edge cases

    @Test func firesOnlyOncePerGesture() {
        // Keeps going well past the threshold, then reverses: still one event.
        let start = 0.0
        let downFrames = move(from: (0.5, 0.9), to: (0.5, 0.2), duration: 0.3, startTime: start)
        let backUp = move(from: (0.5, 0.2), to: (0.5, 0.8), duration: 0.3, startTime: downFrames.last!.timestamp + frameInterval)
        #expect(recognize(downFrames + backUp) == [.swipeDown])
    }

    @Test func shortSwipeBelowThresholdIsIgnored() {
        let frames = gesture(from: (0.5, 0.5), to: (0.5, 0.4))
        #expect(recognize(frames).isEmpty)
    }

    @Test func twoFingerSwipeIsIgnored() {
        let frames = gesture(fingers: 2, from: (0.5, 0.7), to: (0.5, 0.2))
        #expect(recognize(frames).isEmpty)
    }

    @Test func droppingFromFourToThreeFingersStaysIgnored() {
        let four = move(fingers: 4, from: (0.5, 0.8), to: (0.5, 0.7), duration: 0.1)
        let three = move(from: (0.5, 0.7), to: (0.5, 0.2), duration: 0.2, startTime: four.last!.timestamp + frameInterval)
        #expect(recognize(four + three).isEmpty)
    }

    @Test func fourFingerGestureDoesNotPoisonTheNextOne() {
        let four = gesture(fingers: 4, from: (0.5, 0.8), to: (0.5, 0.3))
        let three = gesture(from: (0.5, 0.7), to: (0.5, 0.3), startTime: four.last!.timestamp + 0.1)
        #expect(recognize(four + three) == [.swipeDown])
    }

    @Test func restingThenSwipingStillFires() {
        // Fingers sit still for a second, then swipe quickly.
        let rest = move(from: (0.5, 0.7), to: (0.5, 0.7), duration: 1.0)
        let swipe = move(from: (0.5, 0.7), to: (0.5, 0.35), duration: 0.2, startTime: rest.last!.timestamp + frameInterval)
        #expect(recognize(rest + swipe) == [.swipeDown])
    }

    @Test func fingerCountChangeRestartsTracking() {
        // Half the travel with 3 fingers, a 2-finger blip, then the other half:
        // neither segment alone reaches the threshold.
        let a = move(from: (0.5, 0.7), to: (0.5, 0.58), duration: 0.1)
        let blip = TouchFrame(fingerCount: 2, x: 0.5, y: 0.58, timestamp: a.last!.timestamp + frameInterval)
        let b = move(from: (0.5, 0.58), to: (0.5, 0.46), duration: 0.1, startTime: blip.timestamp + frameInterval)
        #expect(recognize(a + [blip] + b).isEmpty)
    }

    @Test func missedLiftIsTreatedAsNewGesture() {
        // No 0-finger frame between gestures, but a long silence.
        let first = move(from: (0.5, 0.7), to: (0.5, 0.3), duration: 0.2)
        let second = move(from: (0.5, 0.3), to: (0.5, 0.7), duration: 0.2, startTime: first.last!.timestamp + 1.0)
        #expect(recognize(first + second) == [.swipeDown, .swipeUp])
    }

    @Test func thresholdIsConfigurable() {
        let frames = gesture(from: (0.5, 0.5), to: (0.5, 0.4))
        #expect(recognize(frames, configuration: .init(threshold: 0.08)) == [.swipeDown])
    }
}
