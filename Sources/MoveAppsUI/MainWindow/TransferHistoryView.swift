import SwiftUI
import MoveAppsCore

/// The transfer history sheet: one row per completed transfer, most recent first, with the
/// project, direction, date, coloured status and any warnings.
struct TransferHistoryView: View {
    @Environment(MainWindowViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Historique")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
            }
            .padding(18)

            Divider().opacity(0.5)

            if model.history.isEmpty {
                Text("Aucun transfert enregistré")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 10) {
                        LazyVStack(spacing: 10) {
                            ForEach(model.history) { record in
                                HistoryRowView(record: record)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 520, height: 460)
    }
}

/// One history entry, rendered as a glass card so its status colour reads as a real accent
/// rather than flat text.
struct HistoryRowView: View {
    let record: TransferRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(record.projectName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Text(record.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(rootLabel(record.from))
                Image(systemName: "arrow.right")
                Text(rootLabel(record.to))
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(statusColor)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !record.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(record.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warningText(warning), systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(warning.isCritical ? .red : .orange)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(statusColor.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var statusIcon: String {
        switch record.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        case .failed: return .red
        }
    }

    private var statusLabel: String {
        switch record.status {
        case .ok: return "Terminé"
        case .warning: return "Avertissements"
        case .critical: return "Critique — source préservée"
        case .failed: return "Échec"
        }
    }

    private func warningText(_ warning: TransferWarning) -> String {
        switch warning {
        case .venvRecreatedEmpty(let venv):
            return "Venv recréé sans liste de paquets : \(venv.lastPathComponent)"
        case .venvPartialInstall(let venv, let failed):
            return "Venv \(venv.lastPathComponent) : \(failed.count) paquet(s) non réinstallé(s)"
        case .nodeReinstallFailed(let reason):
            return "Échec réinstallation node_modules : \(reason)"
        case .gitDirtyCountChanged(let before, let after):
            return "Nombre de fichiers modifiés git différent (\(before) → \(after))"
        case .gitDeletedFilesDetected(let paths):
            return "Fichiers suivis supprimés détectés : \(paths.count)"
        case .residualPathReferences(let files):
            return "Références au chemin source résiduelles : \(files.count) fichier(s)"
        case .brokenSymlink(let url, let target):
            return "Lien cassé : \(url.lastPathComponent) → \(target)"
        case .crossProjectSymlink(let url, _, let other):
            return "Lien vers un autre projet : \(url.lastPathComponent) → \(other)"
        case .checkoutReferenceWriteFailed(let reason):
            return "Échec d'écriture de la trace de prise : \(reason)"
        }
    }
}
