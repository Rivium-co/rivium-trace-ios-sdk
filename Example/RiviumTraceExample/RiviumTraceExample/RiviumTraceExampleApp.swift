import SwiftUI
import RiviumTrace

@main
struct RiviumTraceExampleApp: App {

    init() {
        // Initialize RiviumTrace SDK
        let config = RiviumTraceConfigBuilder(apiKey: "rv_live_8a51c84264f6360dd8f7c914491d8ba0d51476429d17935e")
            .environment("development")
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
