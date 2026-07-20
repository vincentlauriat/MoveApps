import SwiftUI
import AppKit
import ServiceManagement
import MoveAppsCore

public struct SettingsView: View {
    @Environment(RootPathsController.self) private var rootPaths
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showInDock") private var showInDock = true

    public init() {}

    public var body: some View {
        Form {
            Section {
                rootRow(.active)
                rootRow(.archive)
            } header: {
                Label("Racines", systemImage: "arrow.left.arrow.right")
            }

            Section {
                templatesRow
            } header: {
                Label("Modèles", systemImage: "square.stack.3d.up")
            } footer: {
                Text("Dossier contenant un sous-dossier par modèle de projet, utilisé par « Nouveau projet ».")
            }

            Section("Général") {
                Toggle("Lancer au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Toggle("Afficher dans le Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }

            Section("À propos") {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                    Text("MoveApps")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, idealWidth: 420, minHeight: 320, idealHeight: 360)
    }

    private func rootRow(_ kind: RootKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title(kind), systemImage: kind == .archive ? "archivebox.fill" : "bolt.fill")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Button("Choisir…") {
                    rootPaths.chooseDirectory(for: kind)
                }
                .buttonStyle(.glass)
            }
            Text(rootPaths.displayPath(for: kind))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if rootPaths.needsReconfiguration(kind) {
                Label("Accès perdu — à reconfigurer", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let pickError = rootPaths.lastPickError, pickError.kind == kind {
                Label(pickError.message, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }

    private var templatesRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Dossier de modèles", systemImage: "square.stack.3d.up.fill")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Button("Choisir…") {
                    rootPaths.chooseTemplatesDirectory()
                }
                .buttonStyle(.glass)
            }
            Text(rootPaths.displayTemplatesPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }

    private func title(_ kind: RootKind) -> String {
        switch kind {
        case .active: return "Actif"
        case .archive: return "Archive"
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Reflect the true state if the toggle failed.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
