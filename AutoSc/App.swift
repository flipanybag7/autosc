import SwiftUI

@main
struct AutoScApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        print("[AutoSc] Initializing injection methods...")
        let hidOk = hid_init()
        let gsOk = gs_init()
        let hidErr = String(cString: hid_error())
        let gsErr = String(cString: gs_error())
        print("[AutoSc] IOKit HID: \(hidOk ? "OK" : "FAIL") \(hidErr)")
        print("[AutoSc] GraphicsServices: \(gsOk ? "OK" : "FAIL") \(gsErr)")
        if !hidOk && !gsOk {
            let err = String(cString: inject_error())
            print("[AutoSc] ERROR: \(err)")
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
    @Published var hidError: String = ""
    @Published var gsError: String = ""
    @Published var hidSendFailures: Int = 0

    private init() {}

    func refreshStatus() {
        let inj = TouchInjector.shared
        hidAvailable = hid_ready()
        gsAvailable = gs_ready()
        injectMethod = inj.method
        injectionCount = inj.injectionCount

        hidError = String(cString: hid_error())
        gsError = String(cString: gs_error())
        hidSendFailures = Int(hid_send_failures())

        if injectMethod == "none" {
            lastError = String(cString: inject_error())
        } else {
            lastError = ""
        }
    }
}
