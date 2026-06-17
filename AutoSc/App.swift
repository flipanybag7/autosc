import SwiftUI

@main
struct AutoScApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        hid_init()
        gs_init()
    }

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

    private init() {}

    func refreshStatus() {
        hidAvailable = hid_ready()
        gsAvailable = gs_ready()
        let m = inject_method()
        switch m {
        case 0: injectMethod = "IOKit HID"
        case 1: injectMethod = "GraphicsServices"
        default: injectMethod = "none"
        }
    }
}
