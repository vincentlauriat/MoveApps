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
/// from one column onto the other — or clicking the arrow on a row — prepares a single transfer;
/// checking rows and using the batch bar transfers several at once. A live progress strip appears
/// while a transfer runs, and the toolbar exposes the history and settings.
public struct MainWindowView: View {
    @Environment(MainWindowViewModel.self) private var model

    @State private var showHistory = false

    public init() {}

    public var body: some View {
        @Bindable var model = model

        ZStack {
            backgroundWash

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 1) {
                    RootColumnView(root: .archive)
                    Divider().opacity(0.5)
                    RootColumnView(root: .active)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isRunning {
                    progressStrip
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !model.selection.isEmpty {
                    batchBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.isRunning)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.selection)
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
            TransferPlanView(
                plan: plan,
                existingContainers: model.destinationContainers(for: plan.to),
                onCancel: { model.cancelPending() },
                onConfirm: { keepSymlink, reinstallNode, destinationContainer in
                    model.confirmPending(
                        keepSymlink: keepSymlink,
                        reinstallNode: reinstallNode,
                        destinationContainer: destinationContainer
                    )
                }
            )
        }
        .sheet(item: $model.pendingBatch) { batch in
            BatchTransferView(
                batch: batch,
                existingContainers: model.destinationContainers(for: batch.to),
                onCancel: { model.cancelBatch() },
                onConfirm: { keepSymlink, reinstallNode, folderMode in
                    model.confirmBatch(
                        keepSymlink: keepSymlink,
                        reinstallNode: reinstallNode,
                        folderMode: folderMode
                    )
                }
            )
        }
        .sheet(isPresented: $showHistory) {
            TransferHistoryView()
        }
        .task {
            if model.projects.isEmpty { model.refresh() }
            model.loadHistory()
        }
    }

    /// A faint top-down wash of the system accent colour behind the whole window, just enough
    /// to give the glass panels floating above it something to catch light from.
    private var backgroundWash: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.07), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var progressStrip: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if model.batchTotal > 0 {
                        Text("Projet \(model.batchIndex)/\(model.batchTotal)")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    if let name = model.activeName {
                        Text(name)
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                    }
                }
                Text(model.currentStepText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.18)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Appears when one or more projects are checked: shows the count and transfers them all to
    /// the opposite root.
    private var batchBar: some View {
        let count = model.selection.count
        let destination = model.selectionRoot.map { $0 == .active ? RootKind.archive : .active }
        return HStack(spacing: 12) {
            Text("\(count) projet\(count == 1 ? "" : "s") sélectionné\(count == 1 ? "" : "s")")
                .font(.system(.callout, design: .rounded, weight: .semibold))
            Spacer()
            Button("Désélectionner") { model.clearSelection() }
                .buttonStyle(.glass)
            Button {
                model.prepareBatchTransfer()
            } label: {
                Label("Transférer vers \(rootLabel(destination ?? .archive))", systemImage: "arrow.right")
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.18)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// One column of the main window, listing the projects under a single root and accepting a
/// project dragged from the opposite root.
struct RootColumnView: View {
    @Environment(MainWindowViewModel.self) private var model

    let root: RootKind

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                GlassEffectContainer(spacing: 8) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let groups = projectGroups(model.projects(for: root))
                        if groups.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                // Level-1 folder: a header, then its (level-2) projects indented under it.
                                if let container = group.container {
                                    FolderHeaderView(
                                        name: container,
                                        total: group.projects.count,
                                        selectedCount: model.selectedCount(in: group.projects),
                                        disabled: model.isRunning,
                                        onToggle: { model.toggleFolderSelection(group.projects) }
                                    )
                                    .padding(.top, index == 0 ? 0 : 8)
                                    .padding(.horizontal, 4)
                                }
                                ForEach(group.projects) { project in
                                    MainProjectRowView(
                                        project: project,
                                        disabled: model.isRunning,
                                        isSelected: model.isSelected(project),
                                        onToggleSelect: { model.toggleSelection(project) },
                                        action: { model.prepareTransfer(project) }
                                    )
                                    .padding(.leading, group.container == nil ? 0 : 20)  // nest level-2
                                    .draggable(DraggedProject(path: project.candidate.path, root: project.root))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if isTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(0.55)).interactive(),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTargeted)
        .dropDestination(for: DraggedProject.self) { items, _ in
            guard let dropped = items.first, dropped.root != root else { return false }
            model.prepareTransfer(projectAt: dropped.path)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var emptyState: some View {
        Text(model.isScanning ? "Analyse…" : "Aucun projet")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: root == .archive ? "archivebox.fill" : "bolt.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(rootLabel(root))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(model.displayPath(for: root))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// One project row in a column: a selection checkbox, name, stack tags, and an arrow that starts a
/// single transfer toward the opposite root. Rendered as its own Liquid Glass card so it reads
/// with real relief against the column behind it.
struct MainProjectRowView: View {
    let project: QuickProject
    let disabled: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Désélectionner" : "Sélectionner")

            VStack(alignment: .leading, spacing: 5) {
                Text(project.candidate.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                StackTagRow(tags: sortedTags)
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Label("Transférer vers \(rootLabel(project.destination))", systemImage: "arrow.right")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(disabled)
            .help("Transférer vers \(rootLabel(project.destination))")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassEffect(
            isSelected ? .regular.tint(Color.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .scaleEffect(isHovering ? 1.01 : 1)
        .onHover { hovering in
            guard !disabled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
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

// MARK: - Level-1 grouping

/// A level-1 grouping of a column's projects: either the loose projects sitting directly at the
/// root (`container == nil`, shown first, un-indented) or the projects filed under one level-1
/// folder (shown under a folder header, indented).
private struct ProjectGroup: Identifiable {
    let id: String          // "" for the root-level group, else the container folder name
    let container: String?
    let projects: [QuickProject]
}

/// Splits a column's projects into the root-level group followed by one group per level-1 container
/// folder. Both the loose group and the folder groups are name-sorted; folder groups come after the
/// loose ones so the on-disk hierarchy (level-1 folders holding level-2 projects) reads at a glance.
private func projectGroups(_ projects: [QuickProject]) -> [ProjectGroup] {
    let sorted = projects.sorted {
        $0.candidate.name.localizedCaseInsensitiveCompare($1.candidate.name) == .orderedAscending
    }
    let loose = sorted.filter { $0.candidate.containerName == nil }
    let contained = Dictionary(grouping: sorted.filter { $0.candidate.containerName != nil }) {
        $0.candidate.containerName!
    }

    var groups: [ProjectGroup] = []
    if !loose.isEmpty {
        groups.append(ProjectGroup(id: "", container: nil, projects: loose))
    }
    for name in contained.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
        groups.append(ProjectGroup(id: name, container: name, projects: contained[name] ?? []))
    }
    return groups
}

/// A header marking a level-1 folder that groups the (level-2) project rows below it. Tapping it
/// selects the whole folder for a batch transfer (or deselects it when already fully selected); a
/// tri-state control shows none / some / all selected.
private struct FolderHeaderView: View {
    let name: String
    let total: Int
    let selectedCount: Int
    let disabled: Bool
    let onToggle: () -> Void

    private var selectionIcon: String {
        if selectedCount == 0 { return "circle" }
        if selectedCount == total { return "checkmark.circle.fill" }
        return "minus.circle.fill"
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 7) {
                Image(systemName: selectionIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(selectedCount == 0 ? Color.secondary : Color.accentColor)
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(name)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(total)")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(selectedCount == total && total > 0
              ? "Tout désélectionner dans \(name)"
              : "Sélectionner tout le dossier \(name)")
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .accessibilityLabel("Dossier \(name), \(total) projet\(total == 1 ? "" : "s"), \(selectedCount) sélectionné\(selectedCount == 1 ? "" : "s")")
    }
}
