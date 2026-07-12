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
    @Environment(DashboardViewModel.self) private var dashboard

    @State private var showHistory = false
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        @Bindable var model = model

        ZStack {
            backgroundWash

            VStack(spacing: 0) {
                statHeader

                HStack(alignment: .top, spacing: 1) {
                    RootColumnView(root: .archive, searchText: searchText)
                    Divider().opacity(0.5)
                    RootColumnView(root: .active, searchText: searchText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                Spacer()
                if model.isRunning {
                    progressPill
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !model.selection.isEmpty {
                    batchPill
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 18)
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
            dashboard.refresh()
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

    /// Root counts, disk usage (borrowed straight from the menu-bar dashboard so nothing re-derives
    /// it) and a name search that filters both columns below. Sits on its own material so it reads
    /// as a distinct toolbar strip instead of blending flush into the columns underneath.
    private var statHeader: some View {
        HStack(spacing: 10) {
            statChip(.archive)
            statChip(.active)
            searchField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    private func statChip(_ root: RootKind) -> some View {
        let count = root == .active ? dashboard.activeCount : dashboard.archiveCount
        let size = root == .active ? dashboard.activeSizeBytes : dashboard.archiveSizeBytes
        let tint = rootAccent(root)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3, height: 30)
            Image(systemName: root == .archive ? "archivebox.fill" : "bolt.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(count)")
                        .font(.system(.title3, weight: .bold))
                        .contentTransition(.numericText())
                    Text(rootLabel(root))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(dashboard.isMeasuringDisk ? "Calcul…" : (size.map(ByteFormat.string) ?? "—"))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Rechercher un projet…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minWidth: 180)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progressPill: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if model.batchTotal > 0 {
                        Text("Projet \(model.batchIndex)/\(model.batchTotal)")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    if let name = model.activeName {
                        Text(name)
                            .font(.system(.callout, weight: .semibold))
                    }
                }
                Text(model.currentStepText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.18)),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    /// Appears when one or more projects are checked: shows the count and transfers them all to
    /// the opposite root. A floating pill rather than a full-width bar, so it reads as an overlay
    /// above the columns instead of pushing their content up.
    private var batchPill: some View {
        let count = model.selection.count
        let destination = model.selectionRoot.map { $0 == .active ? RootKind.archive : .active } ?? .archive
        return HStack(spacing: 12) {
            Text("\(count) projet\(count == 1 ? "" : "s") sélectionné\(count == 1 ? "" : "s")")
                .font(.system(.callout, weight: .semibold))
            Button("Désélectionner") { model.clearSelection() }
                .buttonStyle(.glass)
            Button {
                model.prepareBatchTransfer()
            } label: {
                Label("Transférer vers \(rootLabel(destination))", systemImage: "arrow.right")
            }
            .buttonStyle(.glassProminent)
            .tint(rootAccent(destination))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(rootAccent(destination).opacity(0.18)),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

/// One column of the main window, listing the projects under a single root and accepting a
/// project dragged from the opposite root.
struct RootColumnView: View {
    @Environment(MainWindowViewModel.self) private var model

    let root: RootKind
    let searchText: String

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                GlassEffectContainer(spacing: 8) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let groups = projectGroups(filtered(model.projects(for: root)))
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
                                        action: { model.prepareTransfer(project) },
                                        onRelease: { model.releaseCheckout(project) }
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
        let message: String
        if model.isScanning {
            message = "Analyse…"
        } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            message = "Aucun résultat"
        } else {
            message = "Aucun projet"
        }
        return Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    /// Narrows the column to projects whose name matches the search field (all of them when empty).
    private func filtered(_ projects: [QuickProject]) -> [QuickProject] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return projects }
        return projects.filter { $0.candidate.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: root == .archive ? "archivebox.fill" : "bolt.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(rootAccent(root))
            VStack(alignment: .leading, spacing: 2) {
                Text(rootLabel(root))
                    .font(.system(.title3, design: .serif, weight: .semibold))
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
    let onRelease: () -> Void

    @State private var isHovering = false
    @State private var confirmingRelease = false

    private var checkout: CheckoutReference? { project.candidate.checkoutReference }
    private var isLocked: Bool { checkout != nil }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(disabled || isLocked)
            .opacity(isLocked ? 0.35 : 1)
            .help(isSelected ? "Désélectionner" : "Sélectionner")

            VStack(alignment: .leading, spacing: 5) {
                Text(project.candidate.name)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                if let checkout {
                    lockLine(checkout)
                } else {
                    StackTagRow(tags: sortedTags)
                }
            }
            Spacer(minLength: 8)

            Text(ByteFormat.string(project.candidate.sizeBytes))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            if isLocked {
                Button("Libérer") { confirmingRelease = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(disabled)
                    .help("Libérer la trace de prise de ce projet")
            } else {
                Button(action: action) {
                    Label("Transférer vers \(rootLabel(project.destination))", systemImage: "arrow.right")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(rootAccent(project.destination))
                .disabled(disabled)
                .help("Transférer vers \(rootLabel(project.destination))")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .glassEffect(
            glassStyle,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .opacity(isLocked ? 0.85 : 1)
        .scaleEffect(isHovering ? 1.01 : 1)
        .onHover { hovering in
            guard !disabled, !isLocked else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
        .confirmationDialog(
            "Libérer « \(project.candidate.name) » ?",
            isPresented: $confirmingRelease,
            titleVisibility: .visible
        ) {
            Button("Libérer la trace", role: .destructive) { onRelease() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ceci supprime uniquement la trace de prise, pas le contenu réel qui reste sur l'autre Mac. "
                 + "À utiliser seulement si vous êtes sûr que personne d'autre ne travaille dessus.")
        }
    }

    private var glassStyle: Glass {
        if isLocked {
            return .regular.tint(rootAccent(.archive).opacity(0.14))
        }
        return isSelected ? .regular.tint(Color.accentColor.opacity(0.22)).interactive() : .regular.interactive()
    }

    /// The lock badge line shown in place of the stack tags on a checked-out row.
    private func lockLine(_ checkout: CheckoutReference) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Pris par \(checkout.hostName) le \(Self.checkoutDate.string(from: checkout.takenAt))")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(rootAccent(.archive))
    }

    private var sortedTags: [StackTag] {
        project.candidate.stackTags.sorted { $0.rawValue < $1.rawValue }
    }

    private static let checkoutDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

/// French label for a root, matching the convention used across the UI.
func rootLabel(_ kind: RootKind) -> String {
    switch kind {
    case .active: return "Actif"
    case .archive: return "Archive"
    }
}

// MARK: - Level-1 grouping

/// A level-1 entry in a column: either a single loose project sitting directly at the root
/// (`container == nil`, un-indented) or a level-1 folder's projects grouped under it (shown under
/// a folder header, indented). Kept one-project-per-entry for loose items so every entry — folder
/// or project — sorts into a single alphabetical spine in `projectGroups`.
private struct ProjectGroup: Identifiable {
    let id: String
    let container: String?
    let projects: [QuickProject]

    /// What the entry sorts by: the folder name for a container, the project's own name otherwise.
    var sortKey: String { container ?? projects.first?.candidate.name ?? "" }
}

/// One alphabetically-sorted list mixing loose projects and level-1 container folders — a folder
/// and a project with names either side of it in the alphabet land next to each other, rather than
/// all folders being pushed below all loose projects.
private func projectGroups(_ projects: [QuickProject]) -> [ProjectGroup] {
    let sorted = projects.sorted {
        $0.candidate.name.localizedCaseInsensitiveCompare($1.candidate.name) == .orderedAscending
    }
    let loose = sorted.filter { $0.candidate.containerName == nil }
    let contained = Dictionary(grouping: sorted.filter { $0.candidate.containerName != nil }) {
        $0.candidate.containerName!
    }

    var groups: [ProjectGroup] = loose.map {
        ProjectGroup(id: $0.id.absoluteString, container: nil, projects: [$0])
    }
    for (name, projectsInFolder) in contained {
        groups.append(ProjectGroup(id: name, container: name, projects: projectsInFolder))
    }
    return groups.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
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
            HStack(spacing: 6) {
                Image(systemName: selectionIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(selectedCount == 0 ? Color.secondary : Color.accentColor)
                Text(name)
                    .font(.system(.caption, weight: .bold))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(total)")
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
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
