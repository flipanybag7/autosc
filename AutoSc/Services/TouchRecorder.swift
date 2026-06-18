import Foundation
import UIKit
import Combine

enum RecordingState {
    case idle
    case recording
}

final class TouchRecorder: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var actions: [TouchAction] = []
    @Published var elapsedTime: TimeInterval = 0

    private var startTime: Date?
    private var lastActionTime: Date?
    private var touchStartTime: Date?
    private var touchStartPoint: CGPoint?
    private var touchMoved = false
    private var timer: Timer?
    private var longPressTimer: Timer?
    private var longPressTriggered = false
    private var moveDistance: CGFloat = 0

    func startRecording() {
        actions.removeAll()
        state = .recording
        startTime = Date()
        lastActionTime = Date()
        longPressTriggered = false
        moveDistance = 0
        startElapsedTimer()
    }

    func stopRecording() -> [TouchAction] {
        state = .idle
        timer?.invalidate()
        timer = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        let result = actions
        return result
    }

    func recordTouchBegan(at point: CGPoint) {
        guard state == .recording else { return }
        touchStartTime = Date()
        touchStartPoint = point
        touchMoved = false
        longPressTriggered = false
        moveDistance = 0

        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self, self.state == .recording else { return }
            self.longPressTriggered = true
            print("[Recorder] Long press triggered at \(point)")
        }
        print("[Recorder] Touch began at \(point)")
    }

    func recordTouchMoved(to point: CGPoint) {
        guard state == .recording, let start = touchStartPoint else { return }
        let dx = abs(point.x - start.x)
        let dy = abs(point.y - start.y)
        moveDistance = sqrt(dx * dx + dy * dy)
        if moveDistance > 5 {
            if !touchMoved {
                print("[Recorder] Swipe detected — moved \(moveDistance) pts from start")
            }
            touchMoved = true
            longPressTimer?.invalidate()
            longPressTimer = nil
        }
    }

    func recordTouchEnded(at point: CGPoint) {
        guard state == .recording, let start = touchStartPoint else { return }
        longPressTimer?.invalidate()
        longPressTimer = nil

        let delay = delaySinceLastAction()
        lastActionTime = Date()

        if longPressTriggered {
            let duration = Date().timeIntervalSince(touchStartTime ?? Date())
            actions.append(.longPress(at: start, duration: duration, delay: delay))
            print("[Recorder] Recorded long press (\(duration)s) at \(start)")
        } else if touchMoved {
            let duration = Date().timeIntervalSince(touchStartTime ?? Date())
            actions.append(.swipe(from: start, to: point, duration: duration, delay: delay))
            print("[Recorder] Recorded swipe (\(Int(moveDistance))pts, \(String(format: "%.2f", duration))s) \(start) -> \(point)")
        } else {
            actions.append(.tap(at: point, delay: delay))
            print("[Recorder] Recorded tap at \(point)")
        }

        touchStartPoint = nil
        touchStartTime = nil
        longPressTriggered = false
        moveDistance = 0
    }

    private func delaySinceLastAction() -> TimeInterval {
        guard let last = lastActionTime else {
            lastActionTime = Date()
            return 0
        }
        let delay = Date().timeIntervalSince(last)
        lastActionTime = Date()
        return max(0, round(delay * 1000) / 1000)
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }
}
