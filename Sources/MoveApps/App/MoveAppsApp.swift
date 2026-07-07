import SwiftUI
import MoveAppsCore
import MoveAppsUI

@main
struct MoveAppsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var rootPaths: RootPathsController
    @State private var dashboard: DashboardViewModel
    @State private var mainWindow: MainWindowViewModel

    init() {
        let controller = RootPathsController()
        _rootPaths = State(initialValue: controller)
        _dashboard = State(initialValue: DashboardViewModel(rootPaths: controller))
        let historyStore = TransferHistoryStore(fileURL: MainWindowViewModel.defaultHistoryURL())
        _mainWindow = State(initialValue: MainWindowViewModel(rootPaths: controller, historyStore: historyStore))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarDashboardView()
                .environment(rootPaths)
                .environment(dashboard)
        } label: {
            // Transfers only run from the main window now, so the icon reflects its state.
            MenuBarIconView(isBusy: mainWindow.isRunning)
        }
        .menuBarExtraStyle(.window)

        Window("MoveApps", id: "main") {
            MainWindowView()
                .environment(rootPaths)
                .environment(mainWindow)
                .environment(dashboard)
                .onAppear { appDelegate.openMainWindow = { openWindow(id: "main") } }
        }

        // Standalone window (not a sheet in the menu-bar popover, which would dismiss when the
        // template picker's native menu takes focus).
        Window("Nouveau projet", id: "new-project") {
            NewProjectView()
                .environment(rootPaths)
                .environment(dashboard)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(rootPaths)
        }
    }
}
