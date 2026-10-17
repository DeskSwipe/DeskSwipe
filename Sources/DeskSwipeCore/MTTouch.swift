// Memory layout of the private MultitouchSupport framework's touch record.
//
// These structs mirror the C layout the framework hands to contact frame
// callbacks. Every field is a 4- or 8-byte scalar laid out in declaration
// order with natural alignment, so Swift produces exactly the C layout.
// Swift has no static_assert; `MTTouch.layoutIsValid` is checked by the
// unit tests (which build.sh runs before packaging) and again at startup
// before any touch data is read.

public struct MTPoint: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }
}

public struct MTVector: Equatable, Sendable {
    public var position: MTPoint
    public var velocity: MTPoint

    public init(position: MTPoint = .init(), velocity: MTPoint = .init()) {
        self.position = position
        self.velocity = velocity
    }
}

public struct MTTouch: Equatable, Sendable {
    public var frame: Int32                 // 0
    private var padding: Int32 = 0          // 4: aligns timestamp to 8
    public var timestamp: Double            // 8
    public var pathIndex: Int32             // 16
    public var state: Int32                 // 20, see MTTouchState
    public var fingerID: Int32              // 24
    public var handID: Int32                // 28
    public var normalizedVector: MTVector   // 32: position 0...1, y grows away from the user
    public var zTotal: Float                // 48
    public var field9: Int32                // 52
    public var angle: Float                 // 56
    public var majorAxis: Float             // 60
    public var minorAxis: Float             // 64
    public var absoluteVector: MTVector     // 68: millimetres
    public var field14: Int32               // 84
    public var field15: Int32               // 88
    public var zDensity: Float              // 92
                                            // 96 total

    public init(
        frame: Int32 = 0,
        timestamp: Double = 0,
        pathIndex: Int32 = 0,
        state: Int32 = MTTouchState.touching.rawValue,
        fingerID: Int32 = 0,
        handID: Int32 = 0,
        normalizedVector: MTVector = .init(),
        zTotal: Float = 0,
        field9: Int32 = 0,
        angle: Float = 0,
        majorAxis: Float = 0,
        minorAxis: Float = 0,
        absoluteVector: MTVector = .init(),
        field14: Int32 = 0,
        field15: Int32 = 0,
        zDensity: Float = 0
    ) {
        self.frame = frame
        self.timestamp = timestamp
        self.pathIndex = pathIndex
        self.state = state
        self.fingerID = fingerID
        self.handID = handID
        self.normalizedVector = normalizedVector
        self.zTotal = zTotal
        self.field9 = field9
        self.angle = angle
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.absoluteVector = absoluteVector
        self.field14 = field14
        self.field15 = field15
        self.zDensity = zDensity
    }

    public static let expectedSize = 96

    /// True when the Swift layout matches the framework's 96-byte record.
    public static var layoutIsValid: Bool {
        MemoryLayout<MTTouch>.size == expectedSize
            && MemoryLayout<MTTouch>.stride == expectedSize
            && MemoryLayout<MTTouch>.offset(of: \.timestamp) == 8
            && MemoryLayout<MTTouch>.offset(of: \.normalizedVector) == 32
            && MemoryLayout<MTTouch>.offset(of: \.zTotal) == 48
            && MemoryLayout<MTTouch>.offset(of: \.absoluteVector) == 68
            && MemoryLayout<MTTouch>.offset(of: \.zDensity) == 92
    }

    /// Whether this contact is a finger actually on the surface (as opposed
    /// to hovering, lingering after lift, or out of range).
    public var isOnSurface: Bool {
        guard let state = MTTouchState(rawValue: state) else { return false }
        switch state {
        case .makeTouch, .touching, .breakTouch: return true
        default: return false
        }
    }
}

/// Contact states reported in `MTTouch.state`.
public enum MTTouchState: Int32, Sendable {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7
}

extension TouchFrame {
    /// Reduce one contact frame to the fingers that are on the surface.
    public init<C: Collection>(touches: C, timestamp: Double) where C.Element == MTTouch {
        let fingers = touches.filter(\.isOnSurface).map {
            Finger(id: $0.pathIndex, x: $0.normalizedVector.position.x, y: $0.normalizedVector.position.y)
        }
        self.init(fingers: fingers, timestamp: timestamp)
    }
}
