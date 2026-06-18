import SwiftUI
import AVFoundation

let AutoScStopRecordingNotification = Notification.Name("AutoScStopRecording")
let AutoScStopPlayingNotification = Notification.Name("AutoScStopPlaying")

struct RecordView: View {
    @StateObject private var recorder = TouchRecorder()
    @StateObject private var player = MacroPlayer()
    @State private var macroName = ""
    @State private var repeatCount = 1
    @State private var isRecording = false
    @State private var isPlaying = false
    @State private var showTestSwipes = false

    var body: some View {
        ZStack {
            mainContent
                .allowsHitTesting(!isRecording)

            if isRecording {
                TouchCaptureOverlay(recorder: recorder)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        Circle().fill(Color.red).frame(width: 12, height: 12)
                        Text("REC \(String(format: "%.1fs", recorder.elapsedTime))")
                            .font(.headline).foregroundColor(.white)
                        Text("(\(recorder.actions.count))")
                            .font(.subheadline).foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Button(action: stopRecording) {
                            Text("Stop").font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(Color.red).cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(14)
                    .padding(.horizontal).padding(.top, 50)
                    Spacer()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AutoScStopRecordingNotification)) { _ in
            if isRecording { stopRecording() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AutoScStopPlayingNotification)) { _ in
            if isPlaying { stopPlaying() }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)
            statusSection
            actionButtons

            if isRecording || isPlaying {
                Spacer()
            } else if !recorder.actions.isEmpty {
                actionList
            } else {
                Spacer()
                Text("Tap Record, then touch the screen.\nSwipes and taps will be captured.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding()
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
                    .font(.headline).foregroundColor(.white)
                Spacer()
                Text(TouchInjector.shared.method)
                    .font(.caption)
                    .foregroundColor(TouchInjector.shared.canInject ? .green : .red)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.1)).cornerRadius(6)
            }
            if isRecording {
                Text("\(recorder.actions.count) actions captured")
                    .font(.caption).foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05)).cornerRadius(12)
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

            HStack(spacing: 12) {
                Button(action: { showTestSwipes = true }) {
                    Label("Test 10 Swipes", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline).foregroundColor(.cyan)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08)).cornerRadius(8)
                }
                .disabled(!TouchInjector.shared.canInject)
                .sheet(isPresented: $showTestSwipes) {
                    TestSwipeView()
                }

                Spacer()

                if !recorder.actions.isEmpty && !isRecording && !isPlaying {
                    Stepper("Repeat: \(repeatCount)x", value: $repeatCount, in: 1...100)
                        .foregroundColor(.white)
                    Button("Save") { saveMacro() }
                        .foregroundColor(.cyan)
                    Button("Clear") { recorder.actions.removeAll() }
                        .foregroundColor(.red)
                }
            }
            .font(.subheadline)
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
        .listStyle(PlainListStyle()).cornerRadius(12)
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
                    Text("(\(Int(s.x)),\(Int(s.y)))->(\(Int(e.x)),\(Int(e.y)))").font(.caption).foregroundColor(.secondary)
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

// MARK: - Touch Capture Overlay

struct TouchCaptureOverlay: UIViewRepresentable {
    @ObservedObject var recorder: TouchRecorder

    func makeUIView(context: Context) -> TouchCaptureUIView {
        let view = TouchCaptureUIView()
        view.recorder = recorder
        return view
    }

    func updateUIView(_ uiView: TouchCaptureUIView, context: Context) {
        uiView.recorder = recorder
    }
}

final class TouchCaptureUIView: UIView {
    weak var recorder: TouchRecorder?
    private var currentPath: [CGPoint] = []
    private var completedPaths: [[CGPoint]] = []
    private var currentLayer: CAShapeLayer?
    private var completedLayers: [CAShapeLayer] = []
    private var startPoint: CGPoint?
    private var statusBar: UIView!
    private var stopBtn: UIButton!
    private var recLabel: UILabel!
    private var actionsLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
        isMultipleTouchEnabled = true
        setupStatusBar()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupStatusBar() {
        let sb = UIView(frame: CGRect(x: 12, y: 50, width: UIScreen.main.bounds.width - 24, height: 50))
        sb.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        sb.layer.cornerRadius = 14
        sb.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

        let dot = UIView(frame: CGRect(x: 12, y: 19, width: 12, height: 12))
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 6
        sb.addSubview(dot)

        recLabel = UILabel(frame: CGRect(x: 32, y: 0, width: 100, height: 50))
        recLabel.text = "REC 0.0s"
        recLabel.font = .boldSystemFont(ofSize: 16)
        recLabel.textColor = .white
        sb.addSubview(recLabel)

        actionsLabel = UILabel(frame: CGRect(x: 140, y: 0, width: 80, height: 50))
        actionsLabel.text = "(0)"
        actionsLabel.font = .systemFont(ofSize: 14)
        actionsLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        sb.addSubview(actionsLabel)

        stopBtn = UIButton(frame: CGRect(x: sb.frame.width - 82, y: 8, width: 70, height: 34))
        stopBtn.setTitle("Stop", for: .normal)
        stopBtn.titleLabel?.font = .boldSystemFont(ofSize: 15)
        stopBtn.backgroundColor = .systemRed
        stopBtn.layer.cornerRadius = 8
        stopBtn.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        sb.addSubview(stopBtn)

        statusBar = sb
        addSubview(sb)
    }

    @objc private func stopTapped() {
        NotificationCenter.default.post(name: AutoScStopRecordingNotification, object: nil)
    }

    func updateStatusBar(elapsed: TimeInterval, count: Int) {
        DispatchQueue.main.async {
            self.recLabel?.text = "REC \(String(format: "%.1fs", elapsed))"
            self.actionsLabel?.text = "(\(count))"
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let sb = statusBar {
            let converted = convert(point, to: sb)
            if sb.bounds.contains(converted) {
                return sb.hitTest(converted, with: event)
            }
        }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        if let sb = statusBar, sb.frame.contains(point) { return }
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
        if let recorder = recorder {
            updateStatusBar(elapsed: recorder.elapsedTime, count: recorder.actions.count)
        }
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

        if let recorder = recorder {
            updateStatusBar(elapsed: recorder.elapsedTime, count: recorder.actions.count)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
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
        layer.lineWidth = 5
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.shadowColor = UIColor.cyan.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 4
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
        layer.lineWidth = 4
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.opacity = 0.85
        self.layer.addSublayer(layer)
        completedLayers.append(layer)

        let dot = makeDotLayer(at: currentPath[0], color: UIColor.cyan)
        self.layer.addSublayer(dot)
        completedLayers.append(dot)

        let endDot = makeDotLayer(at: currentPath.last!, color: UIColor.systemRed)
        self.layer.addSublayer(endDot)
        completedLayers.append(endDot)
    }

    private func makeDotLayer(at point: CGPoint, color: UIColor = UIColor.cyan) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let size: CGFloat = 14
        layer.path = UIBezierPath(ovalIn: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)).cgPath
        layer.fillColor = color.cgColor
        layer.opacity = 0.9
        return layer
    }
}

// MARK: - Floating Overlay (separate window)

final class FloatingOverlay {
    private static var window: UIWindow?
    private static var mode: Mode = .idle

    enum Mode { case idle, recording, playing }

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
        btn = UIButton(frame: CGRect(x: w - 70, y: 200, width: 58, height: 58))
        btn.layer.cornerRadius = 29
        updateButton()
        btn.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        btn.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged)))
        view.addSubview(btn)
    }

    private func updateButton() {
        switch mode {
        case .recording:
            btn?.backgroundColor = .systemRed
            btn?.setTitle("⬛", for: .normal)
        case .playing:
            btn?.backgroundColor = .systemGreen
            btn?.setTitle("⏹", for: .normal)
        default:
            btn?.backgroundColor = .systemBlue
            btn?.setTitle("AS", for: .normal)
        }
        btn?.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
    }

    @objc private func tapped() {
        let name: Notification.Name
        switch mode {
        case .recording: name = AutoScStopRecordingNotification
        case .playing: name = AutoScStopPlayingNotification
        default: name = Notification.Name("")
        }
        NotificationCenter.default.post(name: name, object: nil)
        FloatingOverlay.hide()
    }

    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        g.view?.center.y += t.y
        g.view?.center.x += t.x
        g.setTranslation(.zero, in: view)
    }
}

// MARK: - Test Swipe Sheet

struct TestSwipeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var running = false
    @State private var log: [String] = []
    @State private var progress = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if running {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    Text("Running swipe \(progress)/10...")
                        .font(.headline).foregroundColor(.cyan)
                } else {
                    Text("Test 10 directional swipes\nVerify the device responds")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: run10Swipes) {
                        Label("Start Test", systemImage: "arrow.triangle.2.circlepath")
                            .font(.title3).foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .cornerRadius(12)
                    }
                    .disabled(!TouchInjector.shared.canInject)
                }

                if !log.isEmpty {
                    List(log, id: \.self) { line in
                        Text(line).font(.caption).foregroundColor(.white)
                            .listRowBackground(Color.white.opacity(0.05))
                    }
                    .listStyle(PlainListStyle()).cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Test Swipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func run10Swipes() {
        running = true
        progress = 0
        log = []

        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let cx = w / 2, cy = h / 2

        DispatchQueue.global(qos: .userInteractive).async {
            let swipes: [(CGPoint, CGPoint, String)] = [
                (CGPoint(x: cx, y: h*0.75), CGPoint(x: cx, y: h*0.25), "Up"),
                (CGPoint(x: cx, y: h*0.25), CGPoint(x: cx, y: h*0.75), "Down"),
                (CGPoint(x: w*0.15, y: cy), CGPoint(x: w*0.85, y: cy), "Right"),
                (CGPoint(x: w*0.85, y: cy), CGPoint(x: w*0.15, y: cy), "Left"),
                (CGPoint(x: w*0.15, y: h*0.75), CGPoint(x: w*0.85, y: h*0.25), "Up-Right"),
                (CGPoint(x: w*0.85, y: h*0.25), CGPoint(x: w*0.15, y: h*0.75), "Down-Left"),
                (CGPoint(x: cx, y: h*0.75), CGPoint(x: cx, y: h*0.25), "Up #2"),
                (CGPoint(x: w*0.85, y: cy), CGPoint(x: w*0.15, y: cy), "Left #2"),
                (CGPoint(x: cx, y: h*0.25), CGPoint(x: cx, y: h*0.75), "Down #2"),
                (CGPoint(x: w*0.15, y: cy), CGPoint(x: w*0.85, y: cy), "Right #2"),
            ]

            let inj = TouchInjector.shared
            for (i, (from, to, name)) in swipes.enumerated() {
                guard inj.canInject else {
                    DispatchQueue.main.async {
                        self.log.append("❌ Stopped — injector unavailable")
                    }
                    break
                }

                inj.swipe(from: from, to: to, duration: 0.35)

                DispatchQueue.main.async {
                    self.progress = i + 1
                    self.log.append("✅ Swipe \(i+1)/10: \(name) (\(Int(from.x)),\(Int(from.y))) -> (\(Int(to.x)),\(Int(to.y)))")
                }
                usleep(500_000)
            }

            DispatchQueue.main.async {
                self.running = false
                self.log.append("🏁 Test complete")
            }
        }
    }
}
