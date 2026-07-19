import AppKit

/// Drives the "Afficher dans le Dock" setting: `LSUIElement` is `true` in `Info.plist` so the
/// OS never force-shows a Dock icon before our code runs, and the actual policy is set here
/// from the persisted `showInDock` preference — the same mechanism `SettingsView`'s toggle
/// uses when the user flips it at runtime.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showInDockDefaultsKey = "showInDock"

    /// Set once from `MoveAppsApp` after the main window's first appearance: AppKit-level events
    /// (Dock icon click) have no direct access to SwiftUI's `openWindow` environment action, so
    /// this closure bridges the two.
    var openMainWindow: (() -> Void)?

    /// Reports whether a transfer is mid-flight. Set from `MoveAppsApp` for the same reason
    /// `openMainWindow` is — AppKit's termination handling has no view of SwiftUI's observable view
    /// models — so `applicationShouldTerminate` can guard ⌘Q against interrupting a move between its
    /// copy and source-deletion steps.
    var isTransferRunning: (() -> Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.showInDockDefaultsKey: true])
        Self.applyDockVisibility()
    }

    /// The menu bar item is the app's persistent presence — closing the main window (in either
    /// Dock mode) must never quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A ⌘Q (or Dock/menu "Quit") while a transfer is running would kill the pipeline between the
    /// copy and the source deletion, leaving a project half-moved. Guard that one case behind an
    /// explicit confirmation; every other quit path stays instantaneous.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isTransferRunning?() == true else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Un transfert est en cours"
        alert.informativeText = "Quitter maintenant risque d'interrompre le transfert en plein vol et de laisser un projet à moitié déplacé. Voulez-vous vraiment quitter ?"
        alert.addButton(withTitle: "Quitter quand même")
        alert.addButton(withTitle: "Annuler")

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Dock icon clicked with no window on screen: bring back the main window (the Active/Archive
    /// lists) instead of leaving the click without effect.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    static func applyDockVisibility() {
        let showInDock = UserDefaults.standard.bool(forKey: showInDockDefaultsKey)
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
