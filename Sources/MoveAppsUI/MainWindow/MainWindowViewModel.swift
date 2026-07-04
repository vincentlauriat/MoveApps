import Foundation
import Observation
import MoveAppsCore

/// Drives the main window: scans both roots into per-column project lists, holds the pending
/// plan awaiting confirmation, runs one transfer at a time through `TransferPipeline`, and
/// persists each completed transfer to the history store.
///
/// Reuses `ProjectListing`'s stateless scan/description helpers but owns all its own transfer
/// state — the main window is now the only surface that runs transfers (the menu bar became a
/// read-only dashboard).
@MainActor
@Observable
public final class MainWindowViewModel {
    public private(set) var projects: [QuickProject] = []
    public private(set) var isScanning = false
    public private(set) var isRunning = false
    public private(set) var activeName: String?
    public private(set) var currentStepText = ""
    public private(set) var lastResult: TransferResult?

    /// A plan built from a drag/drop or row action, awaiting confirmation in the sheet.
    public var pendingPlan: TransferPlan?

    /// Checked projects for a batch transfer. Always confined to a single root (checking a project
    /// in one column clears any checked in the other, since a batch moves one way).
    public private(set) var selection: Set<URL> = []

    /// A batch awaiting confirmation in the batch sheet.
    public var pendingBatch: PendingBatch?

    /// Progress within a running batch (0/0 when not batching), for the progress strip.
    public private(set) var batchIndex = 0
    public private(set) var batchTotal = 0

    /// Completed transfers, most recent first.
    public private(set) var history: [TransferRecord] = []

    private let rootPaths: RootPathsController
    private let historyStore: TransferHistoryStore

    public init(rootPaths: RootPathsController, historyStore: TransferHistoryStore) {
        self.rootPaths = rootPaths
        self.historyStore = historyStore
    }

    /// `~/Library/Application Support/MoveApps/history.json`.
    public static func defaultHistoryURL() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("MoveApps", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    /// The projects currently living under the given root.
    public func projects(for root: RootKind) -> [QuickProject] {
        projects.filter { $0.root == root }
    }

    public func displayPath(for kind: RootKind) -> String {
        rootPaths.displayPath(for: kind)
    }

    // MARK: - Scanning

    public func refresh() {
        let locations = rootPaths.settings.locations
        isScanning = true
        Task {
            let scanned = await Task.detached { ProjectListing.scanSync(locations) }.value
            self.projects = scanned
            self.isScanning = false
        }
    }

    public func loadHistory() {
        Task {
            let all = await historyStore.all()
            self.history = all.reversed()
        }
    }

    // MARK: - Preparing a transfer

    /// Builds a default plan and opens the confirmation sheet. The destination folder defaults to
    /// the project's own container folder (so a project filed under `Outils/` stays under an
    /// `Outils/` on the other side) — the user can change it before confirming.
    public func prepareTransfer(_ project: QuickProject) {
        guard !isRunning else { return }
        pendingPlan = TransferPlan(
            project: project.candidate,
            from: project.root,
            to: project.destination,
            destinationContainer: project.candidate.containerName
        )
    }

    /// The existing category folders on `root`'s side, offered as destination folders in the sheet.
    public func destinationContainers(for root: RootKind) -> [String] {
        ProjectScanner().containerFolders(in: rootPaths.settings.locations.url(for: root))
    }

    /// Resolves a dropped project by its path and prepares a transfer for it.
    public func prepareTransfer(projectAt path: URL) {
        guard let project = projects.first(where: { $0.candidate.path == path }) else { return }
        prepareTransfer(project)
    }

    public func cancelPending() {
        pendingPlan = nil
    }

    // MARK: - Selection & batch

    public func isSelected(_ project: QuickProject) -> Bool {
        selection.contains(project.id)
    }

    /// Toggles a project's checkbox. Since a batch only moves one direction, checking a project
    /// in a different root than the current selection resets the selection to that root first.
    public func toggleSelection(_ project: QuickProject) {
        if let anySelected = selection.first,
           let existing = projects.first(where: { $0.id == anySelected }),
           existing.root != project.root {
            selection.removeAll()
        }
        if selection.contains(project.id) {
            selection.remove(project.id)
        } else {
            selection.insert(project.id)
        }
    }

    public func clearSelection() {
        selection.removeAll()
    }

    /// How many of a folder's projects are currently selected — drives the header's tri-state control.
    public func selectedCount(in folderProjects: [QuickProject]) -> Int {
        folderProjects.reduce(0) { $0 + (selection.contains($1.id) ? 1 : 0) }
    }

    /// Selects every project in a level-1 folder, or deselects them all if they already are.
    /// Like `toggleSelection`, it keeps the selection confined to a single root: toggling a folder
    /// that lives in a different root than the current selection resets the selection first.
    public func toggleFolderSelection(_ folderProjects: [QuickProject]) {
        guard let first = folderProjects.first else { return }
        if let anySelected = selection.first,
           let existing = projects.first(where: { $0.id == anySelected }),
           existing.root != first.root {
            selection.removeAll()
        }
        let ids = folderProjects.map(\.id)
        if ids.allSatisfy({ selection.contains($0) }) {
            ids.forEach { selection.remove($0) }
        } else {
            ids.forEach { selection.insert($0) }
        }
    }

    /// The root the current selection lives under (`nil` when nothing is selected).
    public var selectionRoot: RootKind? {
        guard let first = selection.first else { return nil }
        return projects.first(where: { $0.id == first })?.root
    }

    public var selectedProjects: [QuickProject] {
        projects.filter { selection.contains($0.id) }
    }

    /// Opens the batch confirmation sheet for the currently selected projects.
    public func prepareBatchTransfer() {
        guard !isRunning, let from = selectionRoot else { return }
        let picked = selectedProjects
        guard !picked.isEmpty else { return }
        pendingBatch = PendingBatch(projects: picked, from: from, to: from == .active ? .archive : .active)
    }

    public func cancelBatch() {
        pendingBatch = nil
    }

    /// Confirms a batch: builds one plan per project (each keeping its own container folder, or all
    /// forced to `folderMode`'s folder) and runs them sequentially.
    public func confirmBatch(keepSymlink: Bool, reinstallNode: Bool, folderMode: BatchFolderMode) {
        guard let batch = pendingBatch, !isRunning else { return }
        pendingBatch = nil
        let plans = batch.projects.map { project -> TransferPlan in
            let container: String?
            switch folderMode {
            case .preserveEach:
                container = project.candidate.containerName
            case .fixed(let fixed):
                let cleaned = fixed?.trimmingCharacters(in: .whitespacesAndNewlines)
                container = (cleaned?.isEmpty ?? true) ? nil : cleaned
            }
            return TransferPlan(
                project: project.candidate,
                from: batch.from,
                to: batch.to,
                keepSymlink: keepSymlink,
                reinstallNode: reinstallNode,
                destinationContainer: container
            )
        }
        runBatch(plans)
    }

    /// Confirms the pending plan with the chosen options and destination folder, then transfers.
    public func confirmPending(keepSymlink: Bool, reinstallNode: Bool, destinationContainer: String?) {
        guard let base = pendingPlan else { return }
        pendingPlan = nil
        let cleaned = destinationContainer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TransferPlan(
            project: base.project,
            from: base.from,
            to: base.to,
            keepSymlink: keepSymlink,
            reinstallNode: reinstallNode,
            destinationContainer: (cleaned?.isEmpty ?? true) ? nil : cleaned
        )
        run(plan)
    }

    // MARK: - Running

    private func run(_ plan: TransferPlan) {
        guard !isRunning else { return }
        isRunning = true
        activeName = plan.project.name
        currentStepText = "Démarrage…"
        lastResult = nil

        let locations = rootPaths.settings.locations

        Task {
            let pipeline = TransferPipeline(roots: locations)
            var finalResult: TransferResult?
            for await step in await pipeline.run(plan) {
                self.currentStepText = ProjectListing.describe(step)
                if case .finished(let result) = step {
                    finalResult = result
                    self.lastResult = result
                }
            }
            if let finalResult {
                try? await self.historyStore.append(TransferRecord(plan: plan, result: finalResult))
            }
            self.isRunning = false
            self.activeName = nil
            self.refresh()
            self.loadHistory()
            self.regenerateIndex()
        }
    }

    /// Runs a batch of transfers one after another (never in parallel — the pipeline touches the
    /// filesystem and git, and sequential keeps progress legible and failures isolated). A single
    /// project's failure doesn't abort the rest.
    private func runBatch(_ plans: [TransferPlan]) {
        guard !isRunning, !plans.isEmpty else { return }
        isRunning = true
        batchTotal = plans.count
        batchIndex = 0
        lastResult = nil
        selection.removeAll()

        let locations = rootPaths.settings.locations

        Task {
            let pipeline = TransferPipeline(roots: locations)
            for (offset, plan) in plans.enumerated() {
                self.batchIndex = offset + 1
                self.activeName = plan.project.name
                self.currentStepText = "Démarrage…"
                var finalResult: TransferResult?
                for await step in await pipeline.run(plan) {
                    self.currentStepText = ProjectListing.describe(step)
                    if case .finished(let result) = step {
                        finalResult = result
                        self.lastResult = result
                    }
                }
                if let finalResult {
                    try? await self.historyStore.append(TransferRecord(plan: plan, result: finalResult))
                }
            }
            self.isRunning = false
            self.activeName = nil
            self.batchIndex = 0
            self.batchTotal = 0
            self.refresh()
            self.loadHistory()
            self.regenerateIndex()
        }
    }

    /// Rewrites the unified `INDEX.md` in both roots after a transfer, so the on-disk index always
    /// reflects where projects actually live. Fire-and-forget off the main actor — the transfer
    /// itself already succeeded, so a failure here only leaves a stale index (logged, not surfaced).
    private func regenerateIndex() {
        let locations = rootPaths.settings.locations
        Task.detached { _ = IndexGenerator().write(roots: locations) }
    }
}

/// A batch of projects (all from the same root) awaiting confirmation.
public struct PendingBatch: Identifiable, Sendable {
    public let id = UUID()
    public let projects: [QuickProject]
    public let from: RootKind
    public let to: RootKind
}

/// How a batch assigns each project's destination folder.
public enum BatchFolderMode: Hashable, Sendable {
    /// Every project keeps its own source container folder on the destination side.
    case preserveEach
    /// All projects go into the same folder (`nil` = destination root).
    case fixed(String?)
}
