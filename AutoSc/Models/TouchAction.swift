import Foundation
import CoreGraphics

enum ActionType: String, Codable, CaseIterable {
    case tap
    case longPress
    case swipe
    case wait
}

struct TouchAction: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ActionType
    let startPoint: CGPoint?
    let endPoint: CGPoint?
    let duration: TimeInterval
    let delay: TimeInterval
    let fingerId: Int32

    init(
        id: UUID = UUID(),
        type: ActionType,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        duration: TimeInterval = 0,
        delay: TimeInterval = 0,
        fingerId: Int32 = 0
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.duration = duration
        self.delay = delay
        self.fingerId = fingerId
    }

    static func tap(at point: CGPoint, delay: TimeInterval = 0) -> TouchAction {
        TouchAction(type: .tap, startPoint: point, delay: delay)
    }

    static func longPress(at point: CGPoint, duration: TimeInterval, delay: TimeInterval = 0) -> TouchAction {
        TouchAction(type: .longPress, startPoint: point, duration: duration, delay: delay)
    }

    static func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.3, delay: TimeInterval = 0) -> TouchAction {
        TouchAction(type: .swipe, startPoint: start, endPoint: end, duration: duration, delay: delay)
    }

    static func wait(_ duration: TimeInterval) -> TouchAction {
        TouchAction(type: .wait, duration: duration, delay: duration)
    }
}

extension CGPoint: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let x = try c.decode(CGFloat.self)
        let y = try c.decode(CGFloat.self)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}
