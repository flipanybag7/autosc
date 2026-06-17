import SwiftUI
import AVFoundation

struct RecordView: View {
    @StateObject private var recorder = TouchRecorder()
    @StateObject private var player = MacroPlayer()
    @State private var macroName = ""
    @State private var repeatCount = 1
    @State private var isRecording = false
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            if isRecording {
                TouchCaptureOverlay(
                    recorder: recorder,
                    onCancel: { stopRecording() }
                )
            } else {
                VStack(spacing: 16) {
                    Spacer().frame(height: 20)

                    statusSection

                    actionButtons

                    if !recorder.actions.isEmpty && !isRecording {
                        actionList
                    } else {
                        Spacer()
                        Text("Tap Record, then touch the screen.\nSwipes and taps will be captured with visible paths.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                }
                .padding()
            }
        }
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(isRecording ? Color.red : (isPlaying ? Color.green : Color.gray))
                    .frame(width: 10, height: 10)
                Text(isRecording ? "Recording \(String(format: "%.1fs", recorder.elapsedTime))" :
                     isPlaying ? "Playing \(Int(player.progress * 100))%" :
                     "Idle")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(TouchInjector.shared.method)
                    .font(.caption)
                    .foregroundColor(TouchInjector.shared.canInject ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
            }

            if isRecording {
                Text("\(recorder.actions.count) actions captured — tap Stop when done")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                if isRecording {
                    Button(action: stopRecording) {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.title3).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.red).cornerRadius(12)
                    }
                } else {
                    Button(action: startRecording) {
                        Label("Record", systemImage: "record.circle")
                            .font(.title3).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.red.opacity(0.8)).cornerRadius(12)
                    }
                }

                if !recorder.actions.isEmpty && !isRecording {
                    Button(action: playRecording) {
                        Label("Play", systemImage: "play.circle.fill")
                            .font(.title3).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.green.opacity(0.8)).cornerRadius(12)
                    }
                }

                if isPlaying {
                    Button(action: stopPlaying) {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.title3).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.orange).cornerRadius(12)
                    }
                }
            }

            if !recorder.actions.isEmpty && !isRecording && !isPlaying {
                HStack(spacing: 12) {
                    Stepper("Repeat: \(repeatCount)x", value: $repeatCount, in: 1...100)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Save") {
                        saveMacro()
                    }
                    .foregroundColor(.cyan)
                    Button("Clear") {
                        recorder.actions.removeAll()
                    }
                    .foregroundColor(.red)
                }
                .font(.subheadline)
            }
        }
    }

    private var actionList: some View {
        List {
            ForEach(Array(recorder.actions.enumerated()), id: \.element.id) { idx, action in
                HStack {
                    Text("\(idx + 1)").font(.caption).foregroundColor(.secondary).frame(width: 24)
                    actionLabel(action)
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
        }
        .listStyle(PlainListStyle())
        .cornerRadius(12)
    }

    @ViewBuilder
    private func actionLabel(_ action: TouchAction) -> some View {
        switch action.type {
        case .tap:
            HStack {
                Image(systemName: "hand.tap").foregroundColor(.cyan)
                Text("Tap").foregroundColor(.white)
                if let pt = action.startPoint {
                    Text("(\(Int(pt.x)), \(Int(pt.y)))").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(action.delay * 1000))ms").font(.caption2).foregroundColor(.secondary)
            }
        case .swipe:
            HStack {
                Image(systemName: "hand.draw").foregroundColor(.green)
                Text("Swipe").foregroundColor(.white)
                if let s = action.startPoint, let e = action.endPoint {
                    Text("(\(Int(s.x)),\(Int(s.y)))→(\(Int(e.x)),\(Int(e.y)))").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(String(format: "%.2f", action.duration))s").font(.caption2).foregroundColor(.secondary)
            }
        case .longPress:
            HStack {
                Image(systemName: "hand.point.up.left").foregroundColor(.orange)
                Text("Long Press").foregroundColor(.white)
                if let pt = action.startPoint {
                    Text("(\(Int(pt.x)), \(Int(pt.y)))").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(String(format: "%.2f", action.duration))s").font(.caption2).foregroundColor(.secondary)
            }
        case .wait:
            HStack {
                Image(systemName: "clock").foregroundColor(.yellow)
                Text("Wait").foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.2f", action.duration))s").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func startRecording() {
        recorder.startRecording()
        isRecording = true
        FloatingOverlay.show(mode: .recording)
    }

    private func stopRecording() {
        let _ = recorder.stopRecording()
        isRecording = false
        FloatingOverlay.hide()
    }

    private func playRecording() {
        isPlaying = true
        player.loadActions(recorder.actions)
        FloatingOverlay.show(mode: .playing)
        player.play(loopCount: repeatCount) { _, _ in }
    }

    private func stopPlaying() {
        player.stop()
        isPlaying = false
        FloatingOverlay.hide()
    }

    private func saveMacro() {
        let macro = MacroFile(name: macroName.isEmpty ? "Macro \(Date().formatted())" : macroName, actions: recorder.actions)
        try? MacroStore.save(macro)
    }
}

struct TouchCaptureOverlay: UIViewRepresentable {
    @ObservedObject var recorder: TouchRecorder
    var onCancel: () -> Void

    func makeUIView(context: Context) -> TouchCaptureUIView {
        let view = TouchCaptureUIView()
        view.recorder = recorder
        view.onCancel = onCancel
        return view
    }

    func updateUIView(_ uiView: TouchCaptureUIView, context: Context) {
        uiView.recorder = recorder
        uiView.onCancel = onCancel
    }
}

final class TouchCaptureUIView: UIView {
    weak var recorder: TouchRecorder?
    var onCancel: (() -> Void)?
    private var currentPath: [CGPoint] = []
    private var completedPaths: [[CGPoint]] = []
    private var currentLayer: CAShapeLayer?
    private var completedLayers: [CAShapeLayer] = []
    private var startPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.3)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        startPoint = point
        currentPath = [point]
        recorder?.recordTouchBegan(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        currentPath.append(point)
        recorder?.recordTouchMoved(to: point)
        drawCurrentPath()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        currentPath.append(point)
        recorder?.recordTouchEnded(at: point)

        if currentPath.count > 1 {
            finalizeCurrentPath()
        } else if let sp = startPoint {
            let layer = makeDotLayer(at: sp)
            self.layer.addSublayer(layer)
            completedLayers.append(layer)
        }

        currentPath = []
        currentLayer?.removeFromSuperlayer()
        currentLayer = nil
        startPoint = nil
    }

    private func drawCurrentPath() {
        currentLayer?.removeFromSuperlayer()
        guard currentPath.count >= 2 else { return }

        let layer = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: currentPath[0])
        for i in 1..<currentPath.count {
            path.addLine(to: currentPath[i])
        }
        layer.path = path.cgPath
        layer.strokeColor = UIColor.cyan.cgColor
        layer.lineWidth = 4
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.opacity = 0.9
        self.layer.addSublayer(layer)
        currentLayer = layer
    }

    private func finalizeCurrentPath() {
        currentLayer?.removeFromSuperlayer()

        let layer = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: currentPath[0])
        for i in 1..<currentPath.count {
            path.addLine(to: currentPath[i])
        }
        layer.path = path.cgPath
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.lineWidth = 3
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.opacity = 0.7
        self.layer.addSublayer(layer)
        completedLayers.append(layer)

        let dot = makeDotLayer(at: currentPath[0], color: UIColor.cyan)
        self.layer.addSublayer(dot)
        completedLayers.append(dot)

        let endDot = makeDotLayer(at: currentPath.last!, color: UIColor.red)
        self.layer.addSublayer(endDot)
        completedLayers.append(endDot)
    }

    private func makeDotLayer(at point: CGPoint, color: UIColor = UIColor.cyan) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let size: CGFloat = 12
        layer.path = UIBezierPath(ovalIn: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)).cgPath
        layer.fillColor = color.cgColor
        layer.opacity = 0.8
        return layer
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self
    }
}

final class FloatingOverlay {
    private static var window: UIWindow?
    private static var mode: Mode = .idle

    enum Mode {
        case idle, recording, playing
    }

    static func show(mode: Mode) {
        Self.mode = mode
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .statusBar + 1
            w.backgroundColor = .clear
            w.rootViewController = FloatingVC(mode: mode)
            w.isHidden = false
            Self.window = w
        }
    }

    static func hide() {
        Self.window?.isHidden = true
        Self.window = nil
        Self.mode = .idle
    }

    static func toggle() {
        if Self.window != nil {
            hide()
        }
    }
}

final class FloatingVC: UIViewController {
    private var mode: FloatingOverlay.Mode
    private var btn: UIButton!

    init(mode: FloatingOverlay.Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let w = UIScreen.main.bounds.width
        btn = UIButton(frame: CGRect(x: w - 60, y: 200, width: 50, height: 50))
        btn.layer.cornerRadius = 25
        updateButton()
        btn.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        btn.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged)))
        view.addSubview(btn)
    }

    private func updateButton() {
        switch mode {
        case .recording:
            btn?.backgroundColor = .systemRed
            btn?.setTitle("REC", for: .normal)
        case .playing:
            btn?.backgroundColor = .systemGreen
            btn?.setTitle("▶", for: .normal)
        default:
            btn?.backgroundColor = .systemBlue
            btn?.setTitle("AS", for: .normal)
        }
        btn?.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
    }

    @objc private func tapped() {
        FloatingOverlay.hide()
    }

    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        g.view?.center.y += t.y
        g.view?.center.x += t.x
        g.setTranslation(.zero, in: view)
    }
}
