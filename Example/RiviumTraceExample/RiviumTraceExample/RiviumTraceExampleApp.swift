import SwiftUI
import RiviumTrace

@main
struct RiviumTraceExampleApp: App {

    init() {
        // Initialize RiviumTrace SDK
        let config = RiviumTraceConfigBuilder(apiKey: "rv_live_c1dfb94361eb31420fcce49b475f846eb3fc3bced9d2d113")
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
