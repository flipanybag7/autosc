import SwiftUI

@main
struct AutoScApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        print("[AutoSc] Initializing injection methods...")
        let hidOk = hid_init()
        let gsOk = gs_init()
        print("[AutoSc] IOKit HID: \(hidOk ? "OK" : "FAIL")")
        print("[AutoSc] GraphicsServices: \(gsOk ? "OK" : "FAIL")")
        if !hidOk && !gsOk {
            print("[AutoSc] WARNING: No injection method available!")
        }
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
    @Published var injectionCount: Int = 0
    @Published var lastError: String = ""

    private init() {}

    func refreshStatus() {
        let inj = TouchInjector.shared
        hidAvailable = hid_ready()
        gsAvailable = gs_ready()
        injectMethod = inj.method
        injectionCount = inj.injectionCount
        lastError = inj.lastError

        if injectMethod == "none" {
            if !hidAvailable { lastError = "HID init failed. Binary must be signed with entitlements: ldid -Sentitlements.plist AutoSc" }
            else if !gsAvailable { lastError = "GraphicsServices dlopen failed" }
        } else {
            lastError = ""
        }
    }
}
