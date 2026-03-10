import SwiftUI

@main
struct PosterStudioApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            #if arch(arm64)
            ContentView(appState: appState)
            #else
            Text("仅支持 Apple Silicon（M 系列）")
                .padding(40)
            #endif
        }
        .windowStyle(.titleBar)
    }
}
