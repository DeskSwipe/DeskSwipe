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

/// Fingers that each move on their own path. `paths` maps a finger id to its
/// start and end; fingers listed in `still` stay at their position.
private func moveFingers(
    _ paths: [Int32: (from: (x: Float, y: Float), to: (x: Float, y: Float))],
    still: [Int32: (x: Float, y: Float)] = [:],
    duration: Double,
    startTime: Double = 0
) -> [TouchFrame] {
    let steps = max(1, Int((duration / frameInterval).rounded()))
    return (0...steps).map { i in
        let f = Float(i) / Float(steps)
        var fingers = paths.map { id, p in
            TouchFrame.Finger(id: id, x: p.from.x + (p.to.x - p.from.x) * f, y: p.from.y + (p.to.y - p.from.y) * f)
        }
        fingers += still.map { TouchFrame.Finger(id: $0.key, x: $0.value.x, y: $0.value.y) }
        return TouchFrame(fingers: fingers.sorted { $0.id < $1.id }, timestamp: startTime + Double(i) * frameInterval)
    }
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

    // MARK: - Two-finger scrolling must never count as a 3-finger swipe

    @Test func twoMovingFingersAndARestingThumbAreIgnored() {
        // The average of the three moves 0.27, past the threshold, but the
        // thumb never moves: this is a scroll with a thumb on the pad.
        let frames = moveFingers(
            [1: ((0.45, 0.8), (0.45, 0.4)), 2: ((0.55, 0.8), (0.55, 0.4))],
            still: [3: (0.3, 0.2)],
            duration: 0.2
        )
        #expect(recognize(frames).isEmpty)
    }

    @Test func thumbLandingDuringAScrollIsIgnored() {
        // Two fingers are already scrolling when a third contact lands, and
        // the scroll carries on.
        let scroll = moveFingers([1: ((0.45, 0.9), (0.45, 0.7)), 2: ((0.55, 0.9), (0.55, 0.7))], duration: 0.1)
        let withThumb = moveFingers(
            [1: ((0.45, 0.7), (0.45, 0.2)), 2: ((0.55, 0.7), (0.55, 0.2)), 3: ((0.3, 0.3), (0.3, 0.1))],
            duration: 0.2,
            startTime: scroll.last!.timestamp + frameInterval
        )
        #expect(recognize(scroll + withThumb).isEmpty)
    }

    @Test func scrollThatPicksUpAThirdFingerStaysIgnoredUntilLift() {
        // Even if all three then move together, the gesture began as a scroll.
        let scroll = moveFingers([1: ((0.45, 0.9), (0.45, 0.75)), 2: ((0.55, 0.9), (0.55, 0.75))], duration: 0.1)
        let three = move(from: (0.5, 0.75), to: (0.5, 0.3), duration: 0.2, startTime: scroll.last!.timestamp + frameInterval)
        let next = gesture(from: (0.5, 0.7), to: (0.5, 0.3), startTime: three.last!.timestamp + 0.1)
        let afterLift = [lift(at: three.last!.timestamp + frameInterval)] + next
        #expect(recognize(scroll + three + afterLift) == [.swipeDown])
    }

    @Test func fingersThatJitterWhileLandingStillSwipe() {
        // Real fingers wobble a little as they land; that is not a scroll.
        let landing = [
            TouchFrame(fingers: [.init(id: 1, x: 0.45, y: 0.70)], timestamp: 0),
            TouchFrame(fingers: [.init(id: 1, x: 0.455, y: 0.71), .init(id: 2, x: 0.55, y: 0.70)], timestamp: 0.01),
        ]
        let swipe = moveFingers(
            [1: ((0.455, 0.71), (0.455, 0.3)), 2: ((0.55, 0.70), (0.55, 0.3)), 3: ((0.65, 0.68), (0.65, 0.3))],
            duration: 0.2,
            startTime: 0.02
        )
        #expect(recognize(landing + swipe) == [.swipeDown])
    }

    @Test func swipeWithUnevenFingersStillFires() {
        // One finger travels less than the others, but still well over half.
        let frames = moveFingers(
            [1: ((0.45, 0.7), (0.45, 0.3)), 2: ((0.55, 0.7), (0.55, 0.3)), 3: ((0.65, 0.65), (0.65, 0.5))],
            duration: 0.2
        )
        #expect(recognize(frames) == [.swipeDown])
    }
}
