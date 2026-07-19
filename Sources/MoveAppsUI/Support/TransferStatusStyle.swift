import SwiftUI
import MoveAppsCore

/// Shared visual vocabulary for a transfer's outcome — icon, tint and French label — so the
/// history rows and the main-window result banner render a status identically instead of each
/// keeping their own copy.
extension TransferResult.Status {
    var iconName: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .critical, .failed: return .red
        }
    }

    var label: String {
        switch self {
        case .ok: return "Terminé"
        case .warning: return "Avertissements"
        case .critical: return "Critique — source préservée"
        case .failed: return "Échec"
        }
    }
}
