import SwiftUI

@main
struct RestRoomFinderApp: App {
    init() {
        _ = GoogleMapsConfiguration.isConfigured
        #if DEBUG
        BackendHealthService.runDiagnosticIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
