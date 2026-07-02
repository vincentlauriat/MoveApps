import Foundation
import Observation
import MoveAppsCore

/// Drives the main window: scans both roots into per-column project lists, holds the pending
/// plan awaiting confirmation, runs one transfer at a time through `TransferPipeline`, and
/// persists each completed transfer to the history store.
///
/// Independent from `QuickPickViewModel` — it reuses that type's static scan/description
/// helpers but shares no mutable state, so the menu bar and the main window can each run a
/// transfer without interfering.
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
            let scanned = await Task.detached { QuickPickViewModel.scanSync(locations) }.value
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

    /// Builds a default plan (no options) for the given project and opens the confirmation sheet.
    public func prepareTransfer(_ project: QuickProject) {
        guard !isRunning else { return }
        pendingPlan = TransferPlan(project: project.candidate, from: project.root, to: project.destination)
    }

    /// Resolves a dropped project by its path and prepares a transfer for it.
    public func prepareTransfer(projectAt path: URL) {
        guard let project = projects.first(where: { $0.candidate.path == path }) else { return }
        prepareTransfer(project)
    }

    public func cancelPending() {
        pendingPlan = nil
    }

    /// Confirms the pending plan with the chosen options and starts the transfer.
    public func confirmPending(keepSymlink: Bool, reinstallNode: Bool) {
        guard let base = pendingPlan else { return }
        pendingPlan = nil
        let plan = TransferPlan(
            project: base.project,
            from: base.from,
            to: base.to,
            keepSymlink: keepSymlink,
            reinstallNode: reinstallNode
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
                self.currentStepText = QuickPickViewModel.describe(step)
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
