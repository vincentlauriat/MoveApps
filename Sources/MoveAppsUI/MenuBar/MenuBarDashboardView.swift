import SwiftUI
import AppKit
import MoveAppsCore

/// The menu-bar popup, reworked as a read-only dashboard: at-a-glance stats about both roots,
/// the last transfer, and two actions — create a new project from a template, or open the main
/// window (the only place transfers happen). No project list or in-popup transfer anymore.
public struct MenuBarDashboardView: View {
    @Environment(RootPathsController.self) private var rootPaths
    @Environment(DashboardViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                rootStatCard(.active)
                rootStatCard(.archive)
            }

            lastTransferCard

            Spacer(minLength: 0)

            actions

            indexButton

            Divider().opacity(0.5)

            footer
        }
        .padding(14)
        .frame(width: 340, height: 420)
        .task { model.refresh() }
    }

    private var header: some View {
        HStack {
            Label("MoveApps", systemImage: "arrow.left.arrow.right.circle.fill")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .labelStyle(.titleAndIcon)
            Spacer()
            if model.isScanning || model.isMeasuringDisk {
                ProgressView().controlSize(.small)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Rafraîchir")
            .disabled(model.isScanning)
        }
    }

    private func rootStatCard(_ root: RootKind) -> some View {
        let count = root == .active ? model.activeCount : model.archiveCount
        let size = root == .active ? model.activeSizeBytes : model.archiveSizeBytes
        return VStack(alignment: .leading, spacing: 6) {
            Label(rootLabel(root), systemImage: root == .archive ? "archivebox.fill" : "bolt.fill")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.accentColor)
            Text("\(count)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text("projet\(count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 9))
                Text(model.isMeasuringDisk ? "…" : ByteFormat.string(size))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lastTransferCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dernier transfert")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
            if let record = model.lastTransfer {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon(record.status))
                        .foregroundStyle(statusColor(record.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.projectName)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(rootLabel(record.from))
                            Image(systemName: "arrow.right").font(.system(size: 8))
                            Text(rootLabel(record.to))
                            Text("·")
                            Text(record.date, format: .dateTime.day().month().hour().minute())
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                Text("Aucun transfert enregistré")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                // Open a real window, not a sheet: the menu-bar popover is ephemeral and would
                // dismiss the moment the template picker's native menu takes focus.
                openWindow(id: "new-project")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Nouveau projet", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)

            Button {
                openWindow(id: "main")
            } label: {
                Label("Ouvrir", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    private var indexButton: some View {
        VStack(spacing: 4) {
            Button {
                model.regenerateIndex()
            } label: {
                HStack {
                    if model.isGeneratingIndex {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "list.bullet.rectangle.portrait")
                    }
                    Text("Régénérer l'index")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(model.isGeneratingIndex)
            .help("Réécrit INDEX.md dans les deux racines (Actif + Archive)")

            if let result = model.lastIndexResult {
                switch result {
                case .written(let urls):
                    Text("Index écrit dans \(urls.count) racine\(urls.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.green)
                case .failed(let reason):
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            SettingsLink {
                Label("Réglages", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.glass)
            .help("Réglages")
        }
    }

    private func statusIcon(_ status: TransferResult.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: TransferResult.Status) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .critical, .failed: return .red
        }
    }
}
