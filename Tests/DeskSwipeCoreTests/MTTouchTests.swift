import Testing
@testable import DeskSwipeCore

@Suite("MTTouch layout")
struct MTTouchTests {
    @Test func sizeAndStrideAre96Bytes() {
        #expect(MemoryLayout<MTTouch>.size == 96)
        #expect(MemoryLayout<MTTouch>.stride == 96)
        #expect(MTTouch.layoutIsValid)
    }

    @Test func fieldOffsetsMatchFramework() {
        let layout = MemoryLayout<MTTouch>.self
        #expect(layout.offset(of: \.frame) == 0)
        #expect(layout.offset(of: \.timestamp) == 8)
        #expect(layout.offset(of: \.pathIndex) == 16)
        #expect(layout.offset(of: \.state) == 20)
        #expect(layout.offset(of: \.fingerID) == 24)
        #expect(layout.offset(of: \.handID) == 28)
        #expect(layout.offset(of: \.normalizedVector.position.x) == 32)
        #expect(layout.offset(of: \.normalizedVector.position.y) == 36)
        #expect(layout.offset(of: \.normalizedVector.velocity.x) == 40)
        #expect(layout.offset(of: \.normalizedVector.velocity.y) == 44)
        #expect(layout.offset(of: \.zTotal) == 48)
        #expect(layout.offset(of: \.field9) == 52)
        #expect(layout.offset(of: \.angle) == 56)
        #expect(layout.offset(of: \.majorAxis) == 60)
        #expect(layout.offset(of: \.minorAxis) == 64)
        #expect(layout.offset(of: \.absoluteVector) == 68)
        #expect(layout.offset(of: \.field14) == 84)
        #expect(layout.offset(of: \.field15) == 88)
        #expect(layout.offset(of: \.zDensity) == 92)
    }

    /// Same reads the reference implementation does with raw offsets 32/36.
    @Test func matchesReferenceRawOffsets() {
        let touches = [
            MTTouch(normalizedVector: .init(position: .init(x: 0.25, y: 0.75))),
            MTTouch(normalizedVector: .init(position: .init(x: 0.5, y: 0.5))),
        ]
        touches.withUnsafeBytes { raw in
            #expect(raw.load(fromByteOffset: 32, as: Float.self) == 0.25)
            #expect(raw.load(fromByteOffset: 36, as: Float.self) == 0.75)
            #expect(raw.load(fromByteOffset: 96 + 32, as: Float.self) == 0.5)
            #expect(raw.load(fromByteOffset: 96 + 36, as: Float.self) == 0.5)
        }
    }

    @Test func frameReductionCountsOnlyFingersOnSurface() {
        func touch(_ x: Float, _ y: Float, _ state: MTTouchState) -> MTTouch {
            MTTouch(state: state.rawValue, normalizedVector: .init(position: .init(x: x, y: y)))
        }
        let touches = [
            touch(0.2, 0.4, .touching),
            touch(0.4, 0.6, .makeTouch),
            touch(0.6, 0.8, .breakTouch),
            touch(0.9, 0.9, .hoverInRange),
            touch(0.1, 0.1, .lingerInRange),
        ]
        let frame = TouchFrame(touches: touches, timestamp: 1.5)
        #expect(frame.fingerCount == 3)
        #expect(abs(frame.x - 0.4) < 0.0001)
        #expect(abs(frame.y - 0.6) < 0.0001)
        #expect(frame.timestamp == 1.5)
    }

    @Test func emptyFrameHasZeroFingers() {
        let frame = TouchFrame(touches: [MTTouch](), timestamp: 0)
        #expect(frame.fingerCount == 0)
    }
}
