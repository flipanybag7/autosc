import SwiftUI

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
        }
    }
}

struct StatusView: View {
    @EnvironmentObject var appState: AppState

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
            }

            Section(header: Text("Test")) {
                Button(action: testTap) {
                    HStack {
                        Image(systemName: "hand.tap")
                        Text("Test Tap (center screen)")
                    }
                }
                Button(action: testSwipe) {
                    HStack {
                        Image(systemName: "hand.draw")
                        Text("Test Swipe")
                    }
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
                    Text("v1.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Target")
                    Spacer()
                    Text("TrollStore + Dopamine")
                        .foregroundColor(.secondary)
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
}
