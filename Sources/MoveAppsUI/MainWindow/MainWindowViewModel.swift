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
        }
    }
}
