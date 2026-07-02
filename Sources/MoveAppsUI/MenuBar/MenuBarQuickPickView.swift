import SwiftUI
import MoveAppsCore

/// The window-style content shown when the menu-bar item is clicked: a filterable list of
/// detected projects with a one-tap transfer to the opposite root, plus a live progress line
/// and shortcuts to the main window and settings.
public struct MenuBarQuickPickView: View {
    @Environment(RootPathsController.self) private var rootPaths
    @Environment(QuickPickViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    @State private var filter = ""

    public init() {}

    private var filteredProjects: [QuickProject] {
        guard !filter.isEmpty else { return model.projects }
        return model.projects.filter {
            $0.candidate.name.localizedCaseInsensitiveContains(filter)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            TextField("Filtrer…", text: $filter)
                .textFieldStyle(.roundedBorder)

            if model.isRunning {
                progressLine
            }

            Divider()

            projectList

            Divider()

            footer
        }
        .padding(12)
        .frame(width: 340, height: 420)
        .task { if model.projects.isEmpty { model.refresh() } }
    }

    private var header: some View {
        HStack {
            Text("Projets")
                .font(.headline)
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rafraîchir")
            .disabled(model.isScanning || model.isRunning)
        }
    }

    private var progressLine: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                if let name = model.activeName {
                    Text(name).font(.caption).bold()
                }
                Text(model.currentStepText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if filteredProjects.isEmpty {
                    Text(model.isScanning ? "Analyse…" : "Aucun projet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(filteredProjects) { project in
                        ProjectRowView(project: project, disabled: model.isRunning) {
                            model.transfer(project)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
            } label: {
                Label("Ouvrir MoveApps", systemImage: "macwindow")
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Réglages")
        }
        .buttonStyle(.borderless)
    }
}

/// One project row: name, root badge, stack tags, and a transfer button pointing at the
/// opposite root.
struct ProjectRowView: View {
    let project: QuickProject
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.candidate.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(rootLabel(project.root))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(sortedTags, id: \.self) { tag in
                        Text(tag.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            Spacer()
            Button(action: action) {
                Label(destinationLabel, systemImage: "arrow.right.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .help("Transférer vers \(rootLabel(project.destination))")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var sortedTags: [StackTag] {
        project.candidate.stackTags.sorted { $0.rawValue < $1.rawValue }
    }

    private var destinationLabel: String {
        "→ \(rootLabel(project.destination))"
    }

    private func rootLabel(_ kind: RootKind) -> String {
        switch kind {
        case .active: return "Actif"
        case .archive: return "Archive"
        }
    }
}
