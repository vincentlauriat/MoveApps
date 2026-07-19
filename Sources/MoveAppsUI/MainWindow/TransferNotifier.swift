import AppKit
import UserNotifications
import MoveAppsCore

/// Posts a system notification when a transfer ends in trouble *and the app isn't frontmost* —
/// covering the menu-bar-agent case (`LSUIElement`) where no window is on screen to show the
/// in-window banner. When the app is active the banner already carries the signal, so this stays
/// quiet. Authorization is requested once at launch (`requestAuthorization`); repeat calls never
/// re-prompt, so a lazy request here is harmless if the launch request hasn't run yet.
@MainActor
struct TransferNotifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Notifies about one problematic transfer. A no-op for a clean `.ok` result or while the app
    /// is frontmost. Call once per finished transfer so a batch posts at most one per problem.
    func notifyIfBackgrounded(projectName: String, result: TransferResult) {
        guard result.status != .ok, !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = projectName
        content.body = body(for: result)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func body(for result: TransferResult) -> String {
        switch result.status {
        case .ok:
            return ""
        case .warning:
            return "Transfert terminé avec des avertissements."
        case .critical:
            return "Perte de fichiers possible détectée — la source a été préservée."
        case .failed:
            return "Échec du transfert : \(result.failureReason ?? "raison inconnue")."
        }
    }
}
