import SwiftUI
import RiviumTrace

@main
struct RiviumTraceExampleApp: App {

    init() {
        // Initialize RiviumTrace SDK
        let config = RiviumTraceConfigBuilder(apiKey: "rv_live_df66936060af29df2bf5212e7c7ab38d62289ac1cf1e6f79")
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
