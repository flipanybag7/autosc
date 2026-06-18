import SwiftUI

@main
struct AutoScApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        print("[AutoSc] Initializing injection methods...")
        let hidOk = hid_init()
        let gsOk = gs_init()
        let udOk = userdev_init()
        let cgOk = cgevent_init()
        let kernelOk = kernel_init()
        let hidErr = String(cString: hid_error())
        let gsErr = String(cString: gs_error())
        let udErr = String(cString: userdev_error())
        let cgErr = String(cString: cgevent_error())
        let kernelErr = String(cString: kernel_error())
        print("[AutoSc] IOKit HID: \(hidOk ? "OK" : "FAIL") \(hidErr)")
        print("[AutoSc] GraphicsServices: \(gsOk ? "OK" : "FAIL") \(gsErr)")
        print("[AutoSc] IOHIDUserDevice: \(udOk ? "OK" : "FAIL") \(udErr)")
        print("[AutoSc] CGEvent: \(cgOk ? "OK" : "FAIL") \(cgErr)")
        print("[AutoSc] Kernel Direct: \(kernelOk ? "OK" : "FAIL") \(kernelErr)")
        if !hidOk && !gsOk && !udOk && !cgOk && !kernelOk {
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
    @Published var userdevAvailable: Bool = false
    @Published var userdevError: String = ""
    @Published var cgeventAvailable: Bool = false
    @Published var cgeventError: String = ""
    @Published var helperReady: Bool = false
    @Published var helperError: String = ""
    @Published var tweakConnected: Bool = false
    @Published var kernelAvailable: Bool = false
    @Published var kernelError: String = ""

    private init() {}

    func refreshStatus() {
        let inj = TouchInjector.shared
        hidAvailable = hid_ready()
        gsAvailable = gs_ready()
        injectMethod = inj.method
        injectionCount = inj.injectionCount

        hidError = String(cString: hid_error())
        gsError = String(cString: gs_error())
        userdevError = String(cString: userdev_error())
        userdevAvailable = userdev_ready()
        cgeventAvailable = cgevent_ready()
        cgeventError = String(cString: cgevent_error())
        hidSendFailures = Int(hid_send_failures())
        helperReady = inj.helperReady
        helperError = inj.helperError
        tweakConnected = inj.tweakConnected
        kernelAvailable = kernel_ready()
        kernelError = String(cString: kernel_error())

        if injectMethod == "none" {
            lastError = String(cString: inject_error())
        } else {
            lastError = ""
        }
    }
}
