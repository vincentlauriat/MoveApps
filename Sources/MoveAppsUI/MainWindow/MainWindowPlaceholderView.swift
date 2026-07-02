import SwiftUI
import MoveAppsCore

/// Minimal placeholder for the main window. The full two-column UI is Phase 3; this gives a
/// working, launchable window that lists detected projects and reuses the quick-pick model.
public struct MainWindowPlaceholderView: View {
    @Environment(QuickPickViewModel.self) private var model

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MoveApps")
                    .font(.largeTitle).bold()
                Spacer()
                SettingsLink {
                    Label("Réglages", systemImage: "gearshape")
                }
            }

            Text("Interface complète à venir (Phase 3).")
                .foregroundStyle(.secondary)

            if model.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.currentStepText).font(.callout)
                }
            }

            List(model.projects) { project in
                ProjectRowView(project: project, disabled: model.isRunning) {
                    model.transfer(project)
                }
            }
            .frame(minHeight: 200)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 360)
        .task { if model.projects.isEmpty { model.refresh() } }
    }
}
