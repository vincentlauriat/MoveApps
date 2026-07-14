import SwiftUI
import Sparkle
import MoveAppsCore
import MoveAppsUI

@main
struct MoveAppsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var rootPaths: RootPathsController
    @State private var dashboard: DashboardViewModel
    @State private var mainWindow: MainWindowViewModel
    @State private var debugLog: DebugLogStore

    private let updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Sparkle may check in the background, but never downloads/installs without
        // explicit consent — MoveApps shells out to git/ditto mid-transfer, and a
        // SIGKILL-and-swap during that would be far worse than in a document-based app.
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = false
        return controller
    }()

    init() {
        let controller = RootPathsController()
        _rootPaths = State(initialValue: controller)
        _dashboard = State(initialValue: DashboardViewModel(rootPaths: controller))
        let historyStore = TransferHistoryStore(fileURL: MainWindowViewModel.defaultHistoryURL())
        let sizeCache = ProjectSizeCache()
        let debugLogStore = DebugLogStore()
        _debugLog = State(initialValue: debugLogStore)
        _mainWindow = State(initialValue: MainWindowViewModel(
            rootPaths: controller,
            historyStore: historyStore,
            sizeCache: sizeCache,
            debugLog: debugLogStore
        ))
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
                .environment(debugLog)
                .onAppear { appDelegate.openMainWindow = { openWindow(id: "main") } }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…") {
                    updaterController.checkForUpdates(nil)
                }
            }
        }

        // Opened on demand only (from the main window's toolbar) — never at launch — so it stays
        // out of the way until someone actually wants to trace a slow transfer. `.suppressed`
        // stops macOS window-state restoration from reopening it on its own after a relaunch.
        Window("Debug", id: "debug") {
            DebugLogView()
                .environment(debugLog)
        }
        .defaultSize(width: 520, height: 420)
        .defaultLaunchBehavior(.suppressed)

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
