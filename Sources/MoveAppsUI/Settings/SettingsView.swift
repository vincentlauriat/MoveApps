import SwiftUI
import ServiceManagement
import MoveAppsCore

public struct SettingsView: View {
    @Environment(RootPathsController.self) private var rootPaths
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    public init() {}

    public var body: some View {
        Form {
            Section("Racines") {
                rootRow(.active)
                rootRow(.archive)
            }

            Section("Général") {
                Toggle("Lancer au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("À propos") {
                HStack {
                    Text("MoveApps").font(.headline)
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
    }

    private func rootRow(_ kind: RootKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title(kind)).bold()
                Spacer()
                Button("Choisir…") {
                    rootPaths.chooseDirectory(for: kind)
                }
            }
            Text(rootPaths.displayPath(for: kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if rootPaths.needsReconfiguration(kind) {
                Label("Accès perdu — à reconfigurer", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
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
