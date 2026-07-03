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
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.isRunning)
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
                if let name = model.activeName {
                    Text(name)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
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
                        let projects = model.projects(for: root)
                        if projects.isEmpty {
                            emptyState
                        } else {
                            ForEach(projects) { project in
                                MainProjectRowView(project: project, disabled: model.isRunning) {
                                    model.prepareTransfer(project)
                                }
                                .draggable(DraggedProject(path: project.candidate.path, root: project.root))
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

/// One project row in a column: name, stack tags, and an arrow that starts a transfer toward
/// the opposite root. Rendered as its own Liquid Glass card so it reads with real relief
/// against the column behind it.
struct MainProjectRowView: View {
    let project: QuickProject
    let disabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
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
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
