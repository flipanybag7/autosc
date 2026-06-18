import SwiftUI
import AVFoundation

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

    var body: some View {
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
                    Text("Helper Binary")
                    Spacer()
                    Text(appState.helperAvailable ? (appState.helperRoot ? "Root" : "No root") : "Missing")
                        .foregroundColor(appState.helperRoot ? .green : (appState.helperAvailable ? .orange : .red))
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
                if !appState.statusDetail.isEmpty {
                    Text(appState.statusDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Quick Test")) {
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
                        Text("Go Home + Swipe Test")
                    }
                }
                Text("Swipe injection works system-wide. Press Home after tapping above — the swipe will fire on the home screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    Text("v1.0").foregroundColor(.secondary)
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

    private func testTap() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        TouchInjector.shared.tap(at: CGPoint(x: w / 2, y: h / 2))
    }

    private func testSwipe() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        TouchInjector.shared.swipe(from: CGPoint(x: w / 2, y: h * 0.7),
                                   to: CGPoint(x: w / 2, y: h * 0.3),
                                   duration: 0.4)
    }

    private func test10Swipes() {
        guard !testRunning else { return }
        testRunning = true
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let cx = w / 2, cy = h / 2

        DispatchQueue.global(qos: .userInteractive).async {
            let swipes: [(CGPoint, CGPoint, String)] = [
                (CGPoint(x: cx, y: h*0.7), CGPoint(x: cx, y: h*0.3), "up"),
                (CGPoint(x: cx, y: h*0.3), CGPoint(x: cx, y: h*0.7), "down"),
                (CGPoint(x: w*0.2, y: cy), CGPoint(x: w*0.8, y: cy), "right"),
                (CGPoint(x: w*0.8, y: cy), CGPoint(x: w*0.2, y: cy), "left"),
                (CGPoint(x: w*0.2, y: h*0.7), CGPoint(x: w*0.8, y: h*0.3), "up-right"),
                (CGPoint(x: w*0.8, y: h*0.3), CGPoint(x: w*0.2, y: h*0.7), "down-left"),
                (CGPoint(x: cx, y: h*0.7), CGPoint(x: cx, y: h*0.3), "up"),
                (CGPoint(x: w*0.8, y: cy), CGPoint(x: w*0.2, y: cy), "left"),
                (CGPoint(x: cx, y: h*0.3), CGPoint(x: cx, y: h*0.7), "down"),
                (CGPoint(x: w*0.2, y: cy), CGPoint(x: w*0.8, y: cy), "right"),
            ]

            let inj = TouchInjector.shared
            for (i, (from, to, name)) in swipes.enumerated() {
                guard TouchInjector.shared.canInject else { break }
                inj.swipe(from: from, to: to, duration: 0.35)
                usleep(600000)
                DispatchQueue.main.async {
                    print("Swipe \(i+1)/10: \(name)")
                }
            }

            DispatchQueue.main.async {
                self.testRunning = false
            }
        }
    }

    private func testBackgroundSwipe() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height

        DispatchQueue.global(qos: .userInteractive).async {
            usleep(2000000)
            TouchInjector.shared.swipe(from: CGPoint(x: w/2, y: h*0.7),
                                       to: CGPoint(x: w/2, y: h*0.3),
                                       duration: 0.4)
        }

        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    }
}

final class BackgroundKeepAlive: NSObject {
    static let shared = BackgroundKeepAlive()
    private var player: AVAudioPlayer?
    private var observer: NSObjectProtocol?

    private override init() { super.init() }

    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let sr: Int = 8000
        let dur = 0.1
        let ns = Int(Double(sr) * dur)
        let ds = ns * 2
        var w = Data()
        w.append("RIFF".data(using: .ascii)!); var f = UInt32(36+ds).littleEndian; w.append(Data(bytes: &f, count: 4))
        w.append("WAVE".data(using: .ascii)!); w.append("fmt ".data(using: .ascii)!)
        var z = UInt32(16).littleEndian; w.append(Data(bytes: &z, count: 4))
        var a = UInt16(1).littleEndian; w.append(Data(bytes: &a, count: 2))
        var cc = UInt16(1).littleEndian; w.append(Data(bytes: &cc, count: 2))
        var s = UInt32(sr).littleEndian; w.append(Data(bytes: &s, count: 4))
        var b = UInt32(sr*2).littleEndian; w.append(Data(bytes: &b, count: 4))
        var ba = UInt16(2).littleEndian; w.append(Data(bytes: &ba, count: 2))
        var bp = UInt16(16).littleEndian; w.append(Data(bytes: &bp, count: 2))
        w.append("data".data(using: .ascii)!); var sz = UInt32(ds).littleEndian; w.append(Data(bytes: &sz, count: 4))
        w.append(Data(count: ds))
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sil.wav")
        try? w.write(to: tmp)
        player = try? AVAudioPlayer(contentsOf: tmp)
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.play()
    }
}
