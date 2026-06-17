import Foundation
import Combine

enum PlaybackState {
    case idle
    case playing
    case completed
}

final class MacroPlayer: ObservableObject {
    @Published var state: PlaybackState = .idle
    @Published var currentActionIndex: Int = 0
    @Published var progress: Double = 0
    @Published var loopCount: Int = 1

    private var actions: [TouchAction] = []
    private var currentIndex = 0
    private var isCancelled = false
    private var currentLoop = 0
    private var playbackQueue: DispatchWorkItem?

    var totalActions: Int { actions.count }
    var isPlaying: Bool { state == .playing }
    var canInject: Bool { TouchInjector.shared.canInject }

    func loadActions(_ actions: [TouchAction]) {
        self.actions = actions
        self.currentIndex = 0
        self.progress = 0
        self.state = .idle
    }

    func play(loopCount: Int = 1, onAction: ((TouchAction, Int) -> Void)? = nil) {
        guard !actions.isEmpty else {
            state = .completed
            return
        }
        guard canInject else { return }

        isCancelled = false
        state = .playing
        currentIndex = 0
        currentLoop = 0
        self.loopCount = loopCount
        executeNext(onAction: onAction)
    }

    func stop() {
        isCancelled = true
        state = .idle
        currentIndex = 0
        progress = 0
        playbackQueue?.cancel()
        playbackQueue = nil
    }

    private func executeNext(onAction: ((TouchAction, Int) -> Void)?) {
        guard !isCancelled, state == .playing else { return }

        if currentIndex >= actions.count {
            currentLoop += 1
            if currentLoop < loopCount {
                currentIndex = 0
            } else {
                state = .completed
                progress = 1.0
                return
            }
        }

        let action = actions[currentIndex]
        currentActionIndex = currentIndex
        progress = Double(currentIndex) / Double(max(1, actions.count))
        onAction?(action, currentIndex)

        DispatchQueue.global(qos: .userInteractive).async {
            self.performAction(action)
        }

        currentIndex += 1

        let totalDelay = action.delay + action.duration + 0.02
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeNext(onAction: onAction)
        }
        playbackQueue = workItem
        DispatchQueue.global(qos: .userInteractive).asyncAfter(
            deadline: .now() + totalDelay, execute: workItem)
    }

    private func performAction(_ action: TouchAction) {
        let injector = TouchInjector.shared
        switch action.type {
        case .tap:
            if let pt = action.startPoint {
                injector.tap(at: pt)
            }
        case .swipe:
            if let start = action.startPoint, let end = action.endPoint {
                injector.swipe(from: start, to: end, duration: action.duration)
            }
        case .longPress:
            if let pt = action.startPoint {
                injector.longPress(at: pt, duration: action.duration)
            }
        case .wait:
            Thread.sleep(forTimeInterval: action.duration)
        }
    }
}
