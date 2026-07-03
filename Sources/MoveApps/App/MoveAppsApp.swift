import SwiftUI
import MoveAppsCore
import MoveAppsUI

@main
struct MoveAppsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var rootPaths: RootPathsController
    @State private var quickPick: QuickPickViewModel
    @State private var mainWindow: MainWindowViewModel

    init() {
        let controller = RootPathsController()
        _rootPaths = State(initialValue: controller)
        _quickPick = State(initialValue: QuickPickViewModel(rootPaths: controller))
        let historyStore = TransferHistoryStore(fileURL: MainWindowViewModel.defaultHistoryURL())
        _mainWindow = State(initialValue: MainWindowViewModel(rootPaths: controller, historyStore: historyStore))
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
            MainWindowView()
                .environment(rootPaths)
                .environment(mainWindow)
        }

        Settings {
            SettingsView()
                .environment(rootPaths)
        }
    }
}
