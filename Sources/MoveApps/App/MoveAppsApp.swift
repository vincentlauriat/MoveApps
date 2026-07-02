import SwiftUI
import MoveAppsUI

@main
struct MoveAppsApp: App {
    @State private var rootPaths: RootPathsController
    @State private var quickPick: QuickPickViewModel

    init() {
        let controller = RootPathsController()
        _rootPaths = State(initialValue: controller)
        _quickPick = State(initialValue: QuickPickViewModel(rootPaths: controller))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarQuickPickView()
                .environment(rootPaths)
                .environment(quickPick)
        } label: {
            MenuBarIconView(isBusy: quickPick.isRunning)
        }
        .menuBarExtraStyle(.window)

        Window("MoveApps", id: "main") {
            MainWindowPlaceholderView()
                .environment(rootPaths)
                .environment(quickPick)
        }

        Settings {
            SettingsView()
                .environment(rootPaths)
        }
    }
}
