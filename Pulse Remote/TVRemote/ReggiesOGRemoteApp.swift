import SwiftUI
import WidgetKit

@main
struct PulseRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Color.clear
            } else {
                TVRemoteAppView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
