import SwiftUI
import UniformTypeIdentifiers
import MoveAppsCore

/// The payload dragged between the two root columns. Carries just enough to look the full
/// project back up in the view model (its path is its stable identity across scans).
struct DraggedProject: Codable, Transferable {
    let path: URL
    let root: RootKind

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// The main window: two columns (archive on the left, active on the right). Dragging a project
/// from one column onto the other — or clicking the arrow on a row — prepares a transfer and
/// opens the confirmation sheet. A live progress strip appears while a transfer runs, and the
/// toolbar exposes the history and settings.
public struct MainWindowView: View {
    @Environment(MainWindowViewModel.self) private var model

    @State private var showHistory = false

    public init() {}

    public var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                RootColumnView(root: .archive)
                Divider()
                RootColumnView(root: .active)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isRunning {
                Divider()
                progressStrip
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refresh()
                } label: {
                    Label("Rafraîchir", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning || model.isRunning)

                Button {
                    model.loadHistory()
                    showHistory = true
                } label: {
                    Label("Historique", systemImage: "clock.arrow.circlepath")
                }

                SettingsLink {
                    Label("Réglages", systemImage: "gearshape")
                }
            }
        }
        .sheet(item: $model.pendingPlan) { plan in
            TransferPlanView(plan: plan)
        }
        .sheet(isPresented: $showHistory) {
            TransferHistoryView()
        }
        .task {
            if model.projects.isEmpty { model.refresh() }
            model.loadHistory()
        }
    }

    private var progressStrip: some View {
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
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One column of the main window, listing the projects under a single root and accepting a
/// project dragged from the opposite root.
struct RootColumnView: View {
    @Environment(MainWindowViewModel.self) private var model

    let root: RootKind

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let projects = model.projects(for: root)
                    if projects.isEmpty {
                        Text(model.isScanning ? "Analyse…" : "Aucun projet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(projects) { project in
                            MainProjectRowView(project: project, disabled: model.isRunning) {
                                model.prepareTransfer(project)
                            }
                            .draggable(DraggedProject(path: project.candidate.path, root: project.root))
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .dropDestination(for: DraggedProject.self) { items, _ in
            guard let dropped = items.first, dropped.root != root else { return false }
            model.prepareTransfer(projectAt: dropped.path)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rootLabel(root))
                .font(.headline)
            Text(model.displayPath(for: root))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
    }
}

/// One project row in a column: name, stack tags, and an arrow that starts a transfer toward
/// the opposite root.
struct MainProjectRowView: View {
    let project: QuickProject
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.candidate.name)
                    .font(.body)
                    .lineLimit(1)
                if !sortedTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(sortedTags, id: \.self) { tag in
                            Text(tag.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            Spacer()
            Button(action: action) {
                Label("Transférer vers \(rootLabel(project.destination))", systemImage: "arrow.right.circle")
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
}

/// French label for a root, matching the convention used across the UI.
func rootLabel(_ kind: RootKind) -> String {
    switch kind {
    case .active: return "Actif"
    case .archive: return "Archive"
    }
}
