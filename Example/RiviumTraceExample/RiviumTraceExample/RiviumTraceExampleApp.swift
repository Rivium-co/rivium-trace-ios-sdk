import SwiftUI
import RiviumTrace

@main
struct RiviumTraceExampleApp: App {

    init() {
        // Initialize RiviumTrace SDK
        let config = RiviumTraceConfigBuilder(apiKey: "rv_live_d15ea4bd5e2c7a4c9e55576433c0e78aaed005a0036d89ac")
            .environment("development")
            .apiUrl("http://localhost:3001")
            .release(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .debug(true)
            .captureUncaughtExceptions(true)
            .captureAnr(true)
            .anrTimeoutMs(5000)
            .maxBreadcrumbs(30)
            .sampleRate(1.0)
            .enableOfflineStorage(true)
            .build()

        RiviumTrace.shared.initialize(config: config)

        // Enable logging
        RiviumTrace.shared.enableLogging(
            sourceId: "ios-demo-app",
            sourceName: "iOS Demo App"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
