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

    private func filteredProjects(for root: RootKind) -> [QuickProject] {
        model.projects
            .filter { $0.root == root }
            .filter { filter.isEmpty || $0.candidate.name.localizedCaseInsensitiveContains(filter) }
    }

    public var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            header

            searchField

            if model.isRunning {
                progressLine
                    .transition(.opacity)
            }

            Divider().opacity(0.5)

            projectList

            Divider().opacity(0.5)

            footer
        }
        .padding(14)
        .frame(width: 340, height: 420)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.isRunning)
        .task { if model.projects.isEmpty { model.refresh() } }
        .sheet(item: $model.pendingPlan) { plan in
            TransferPlanView(
                plan: plan,
                onCancel: { model.cancelPending() },
                onConfirm: { keepSymlink, reinstallNode in
                    model.confirmPending(keepSymlink: keepSymlink, reinstallNode: reinstallNode)
                }
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Projets")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Spacer()
            if model.isScanning {
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
            .disabled(model.isScanning || model.isRunning)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Filtrer…", text: $filter)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.18)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    /// Two sections, one per root, instead of one flat alphabetical list mixing both — the flat
    /// list made it impossible to tell at a glance which projects were active vs. archived
    /// without reading each row's small root label individually.
    private var projectList: some View {
        ScrollView {
            GlassEffectContainer(spacing: 10) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    rootSection(.active)
                    rootSection(.archive)
                }
            }
        }
    }

    private func rootSection(_ root: RootKind) -> some View {
        let projects = filteredProjects(for: root)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: root == .archive ? "archivebox.fill" : "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(rootLabel(root))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(projects.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            if projects.isEmpty {
                Text(model.isScanning ? "Analyse…" : "Aucun projet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(projects) { project in
                        ProjectRowView(project: project, disabled: model.isRunning) {
                            model.prepareTransfer(project)
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
            .buttonStyle(.glass)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .help("Réglages")
        }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(project.candidate.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                if let container = project.candidate.containerName {
                    Label(container, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                StackTagRow(tags: sortedTags)
            }
            Spacer()
            Button(action: action) {
                Label(destinationLabel, systemImage: "arrow.right")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(disabled)
            .help("Transférer vers \(rootLabel(project.destination))")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sortedTags: [StackTag] {
        project.candidate.stackTags.sorted { $0.rawValue < $1.rawValue }
    }

    private var destinationLabel: String {
        "→ \(rootLabel(project.destination))"
    }
}
