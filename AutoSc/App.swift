import SwiftUI

@main
struct AutoScApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(appState)
        }
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var injectMethod: String = "none"
    @Published var hidAvailable: Bool = false
    @Published var gsAvailable: Bool = false
    @Published var helperAvailable: Bool = false
    @Published var helperRoot: Bool = false
    @Published var statusDetail: String = ""

    private init() {}

    func refreshStatus() {
        let inj = TouchInjector.shared
        helperAvailable = helper_ready()
        helperRoot = helper_is_root()
        hidAvailable = hid_ready()
        gsAvailable = gs_ready()
        injectMethod = inj.method
        statusDetail = inj.statusDetail
    }
}
