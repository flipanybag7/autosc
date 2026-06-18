import SwiftUI
import AVFoundation
    import UIKit

func goToHomeScreen() {
    let app = UIApplication.shared
    let selector = #selector(URLSessionTask.suspend)
    if app.responds(to: selector) {
        app.perform(selector)
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }
                .tag(0)

            MacroListView()
                .tabItem {
                    Label("Macros", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            LuaEditorView()
                .tabItem {
                    Label("Lua", systemImage: "chevron.left.slash.chevron.right")
                }
                .tag(2)

            StatusView()
                .tabItem {
                    Label("Status", systemImage: "info.circle")
                }
                .tag(3)
        }
        .accentColor(.cyan)
        .onAppear {
            appState.refreshStatus()
            BackgroundKeepAlive.shared.start()
        }
    }
}

struct StatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var testRunning = false
    @State private var bgTestScheduled = false
    @State private var log: [String] = []
    @State private var showLog = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Injection Method")) {
                    HStack {
                        Text("Active Method")
                        Spacer()
                        Text(appState.injectMethod)
                            .foregroundColor(appState.injectMethod != "none" ? .green : .red)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("IOKit HID")
                        Spacer()
                        Text(appState.hidAvailable ? "Available" : "Unavailable")
                            .foregroundColor(appState.hidAvailable ? .green : .red)
                    }
                    HStack {
                        Text("GraphicsServices")
                        Spacer()
                        Text(appState.gsAvailable ? "Available" : "Unavailable")
                            .foregroundColor(appState.gsAvailable ? .green : .red)
                    }
                    if !appState.lastError.isEmpty {
                        HStack {
                            Text("Error")
                            Spacer()
                            Text(appState.lastError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if !appState.hidError.isEmpty {
                        HStack {
                            Text("HID Detail")
                            Spacer()
                            Text(appState.hidError)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if !appState.gsError.isEmpty {
                        HStack {
                            Text("GS Detail")
                            Spacer()
                            Text(appState.gsError)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text("IOHIDUserDevice")
                        Spacer()
                        Text(appState.userdevAvailable ? "Available" : "Unavailable")
                            .foregroundColor(appState.userdevAvailable ? .green : .red)
                    }
                    if !appState.userdevError.isEmpty {
                        HStack {
                            Text("UserDevice Detail")
                            Spacer()
                            Text(appState.userdevError)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text("CGEvent")
                        Spacer()
                        Text(appState.cgeventAvailable ? "Available" : "Unavailable")
                            .foregroundColor(appState.cgeventAvailable ? .green : .red)
                    }
                    if !appState.cgeventError.isEmpty {
                        HStack {
                            Text("CGEvent Detail")
                            Spacer()
                            Text(appState.cgeventError)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text("Helper Binary")
                        Spacer()
                        Text(appState.helperReady ? "Ready" : "Not Embedded")
                            .foregroundColor(appState.helperReady ? .green : .orange)
                    }
                    if !appState.helperError.isEmpty {
                        HStack {
                            Text("Helper Detail")
                            Spacer()
                            Text(appState.helperError)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text("SpringBoard Tweak")
                        Spacer()
                        Text(appState.tweakConnected ? "Connected" : "Not Found")
                            .foregroundColor(appState.tweakConnected ? .green : .orange)
                    }
                    HStack {
                        Text("Events Injected")
                        Spacer()
                        Text("\(appState.injectionCount)")
                            .foregroundColor(.cyan)
                    }
                    HStack {
                        Text("Send Failures")
                        Spacer()
                        Text("\(appState.hidSendFailures)")
                            .foregroundColor(appState.hidSendFailures > 0 ? .red : .green)
                    }
                }

                Section(header: Text("Quick Tests")) {
                    Button(action: testTap) {
                        HStack {
                            Image(systemName: "hand.tap")
                            Text("Test Tap (center)")
                        }
                    }
                    Button(action: testSwipe) {
                        HStack {
                            Image(systemName: "hand.draw")
                            Text("Test Swipe (up)")
                        }
                    }
                    Button(action: test10Swipes) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(testRunning ? "Running..." : "Test 10 Swipes (all directions)")
                        }
                    }
                    .disabled(testRunning)
                }

                Section(header: Text("Background")) {
                    Button(action: testBackgroundSwipe) {
                        HStack {
                            Image(systemName: "arrow.up.doc")
                            Text(bgTestScheduled ? "Scheduled (go home)..." : "Go Home + Swipe Test")
                        }
                    }
                    .disabled(bgTestScheduled)
                    Text("Tap above, then press the Home button. A swipe will fire on the home screen after 3 seconds.")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section(header: Text("Background Keep-Alive")) {
                    HStack {
                        Text("Audio Session")
                        Spacer()
                        Text(BackgroundKeepAlive.shared.isActive ? "Active" : "Inactive")
                            .foregroundColor(BackgroundKeepAlive.shared.isActive ? .green : .red)
                    }
                    HStack {
                        Text("Background Task")
                        Spacer()
                        Text(BackgroundKeepAlive.shared.bgTaskActive ? "Registered" : "Waiting (enter bg)")
                            .foregroundColor(BackgroundKeepAlive.shared.bgTaskActive ? .green : .orange)
                    }
                    Text("Go home to test — a swipe fires on the home screen after 3s.")
                        .font(.caption).foregroundColor(.secondary)
                }

                if !log.isEmpty {
                    Section(header: Text("Log")) {
                        ForEach(log, id: \.self) { line in
                            Text(line).font(.caption).foregroundColor(.secondary)
                        }
                        Button("Clear Log") { log.removeAll() }
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Refresh")) {
                    Button(action: { appState.refreshStatus() }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Re-detect methods")
                        }
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("AutoSc")
                        Spacer()
                        Text("v1.1").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Target")
                        Spacer()
                        Text("TrollStore + Dopamine").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Status")
        }
    }

    private func testTap() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        TouchInjector.shared.tap(at: CGPoint(x: w / 2, y: h / 2))
        log.append("Tap at (\(Int(w/2)), \(Int(h/2)))")
    }

    private func testSwipe() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        TouchInjector.shared.swipe(from: CGPoint(x: w / 2, y: h * 0.7),
                                   to: CGPoint(x: w / 2, y: h * 0.3),
                                   duration: 0.4)
        log.append("Swipe up from (\(Int(w/2)), \(Int(h*0.7)))")
    }

    private func test10Swipes() {
        guard !testRunning else { return }
        testRunning = true
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let cx = w / 2, cy = h / 2

        log.append("--- 10 Swipe Test ---")

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
                guard TouchInjector.shared.canInject else {
                    DispatchQueue.main.async {
                        self.log.append("Stopped — injector unavailable")
                    }
                    break
                }
                inj.swipe(from: from, to: to, duration: 0.35)
                DispatchQueue.main.async {
                    self.log.append("Swipe \(i+1)/10: \(name)")
                }
                usleep(500_000)
            }

            DispatchQueue.main.async {
                self.testRunning = false
                self.log.append("--- Test Complete ---")
            }
        }
    }

    private func testBackgroundSwipe() {
        bgTestScheduled = true
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height

        log.append("Background swipe scheduled... go home!")

        DispatchQueue.global(qos: .userInteractive).async {
            usleep(3_000_000)
            TouchInjector.shared.swipe(from: CGPoint(x: w/2, y: h*0.7),
                                        to: CGPoint(x: w/2, y: h*0.3),
                                        duration: 0.4)
            DispatchQueue.main.async {
                self.log.append("Background swipe fired")
                self.bgTestScheduled = false
            }
        }

        goToHomeScreen()
    }
}

final class BackgroundKeepAlive: NSObject {
    static let shared = BackgroundKeepAlive()
    private var player: AVAudioPlayer?
    private var observer: NSObjectProtocol?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private(set) var isActive = false
    private(set) var bgTaskActive = false

    private override init() { super.init() }

    func start() {
        setupAudio()
        setupNotifications()
        isActive = true
    }

    func stop() {
        player?.stop()
        player = nil
        endBackgroundTask()
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        isActive = false
    }

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
        }

        let sr: Int = 8000
        let dur = 1.0
        let ns = Int(Double(sr) * dur)
        let ds = ns * 2

        var w = Data()
        let writeHeader: (String) -> Void = { s in w.append(s.data(using: .ascii)!) }

        writeHeader("RIFF")
        var fileSize = UInt32(36 + ds).littleEndian
        w.append(Data(bytes: &fileSize, count: 4))
        writeHeader("WAVE")
        writeHeader("fmt ")
        var chunkSize = UInt32(16).littleEndian
        w.append(Data(bytes: &chunkSize, count: 4))
        var audioFormat = UInt16(1).littleEndian
        w.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(1).littleEndian
        w.append(Data(bytes: &numChannels, count: 2))
        var sampleRate = UInt32(sr).littleEndian
        w.append(Data(bytes: &sampleRate, count: 4))
        var byteRate = UInt32(sr * 2).littleEndian
        w.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        w.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        w.append(Data(bytes: &bitsPerSample, count: 2))
        writeHeader("data")
        var dataSize = UInt32(ds).littleEndian
        w.append(Data(bytes: &dataSize, count: 4))
        w.append(Data(count: ds))

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("silence.wav")
        try? w.write(to: tmp)

        player = try? AVAudioPlayer(contentsOf: tmp)
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.prepareToPlay()
        player?.play()
    }

    private func setupBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AutoScKeepAlive") { [weak self] in
            self?.endBackgroundTask()
            self?.scheduleNewBackgroundTask()
        }
        bgTaskActive = backgroundTaskID != .invalid
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        bgTaskActive = false
    }

    private func scheduleNewBackgroundTask() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.setupBackgroundTask()
        }
    }

    private func setupNotifications() {
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.setupBackgroundTask()
            self?.player?.play()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.endBackgroundTask()
        }
    }
}
