import Foundation
import Observation
import MoveAppsCore

/// A detected project together with the root it currently lives under, so a transfer can be
/// aimed at the opposite root without re-deriving its location.
public struct QuickProject: Sendable, Identifiable, Hashable {
    public var candidate: ProjectCandidate
    public var root: RootKind
    public var id: URL { candidate.path }

    /// The root a transfer would move this project to.
    public var destination: RootKind { root == .active ? .archive : .active }
}

/// Drives the menu-bar quick pick: scans both roots for projects and runs one transfer at a
/// time through `TransferPipeline`, surfacing the current step for a lightweight progress line.
@MainActor
@Observable
public final class QuickPickViewModel {
    public private(set) var projects: [QuickProject] = []
    public private(set) var isScanning = false
    public private(set) var isRunning = false
    public private(set) var activeName: String?
    public private(set) var currentStepText = ""
    public private(set) var lastResult: TransferResult?

    /// A plan built from a row action, awaiting confirmation in the sheet — mirrors
    /// `MainWindowViewModel.pendingPlan` so both surfaces share the same confirm-before-transfer
    /// choreography instead of the menu bar transferring instantly on tap.
    public var pendingPlan: TransferPlan?

    private let rootPaths: RootPathsController

    public init(rootPaths: RootPathsController) {
        self.rootPaths = rootPaths
    }

    public func refresh() {
        let locations = rootPaths.settings.locations
        isScanning = true
        Task {
            let scanned = await Task.detached { Self.scanSync(locations) }.value
            self.projects = scanned
            self.isScanning = false
        }
    }

    // MARK: - Preparing a transfer

    /// Builds a default plan (no options) for the given project and opens the confirmation sheet.
    public func prepareTransfer(_ project: QuickProject) {
        guard !isRunning else { return }
        pendingPlan = TransferPlan(project: project.candidate, from: project.root, to: project.destination)
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
            for await step in await pipeline.run(plan) {
                self.currentStepText = Self.describe(step)
                if case .finished(let result) = step {
                    self.lastResult = result
                }
            }
            self.isRunning = false
            self.activeName = nil
            self.refresh()
        }
    }

    // MARK: - Scanning (off the main actor)

    nonisolated static func scanSync(_ locations: RootLocations) -> [QuickProject] {
        let scanner = ProjectScanner()
        var result: [QuickProject] = []

        for kind in RootKind.allCases {
            let root = locations.url(for: kind)
            let candidates = scanner.scan(root)
            result.append(contentsOf: candidates.map { QuickProject(candidate: $0, root: kind) })
        }

        return result.sorted {
            $0.candidate.name.localizedCaseInsensitiveCompare($1.candidate.name) == .orderedAscending
        }
    }

    // MARK: - Step descriptions

    static func describe(_ step: TransferStep) -> String {
        switch step {
        case .detectingStack: return "Détection de la stack…"
        case .materializingICloud(let remaining): return "Matérialisation iCloud (\(remaining) restants)…"
        case .capturingVenvState(let venv): return "Capture du venv \(venv.lastPathComponent)…"
        case .snapshottingGitBefore: return "Instantané git (avant)…"
        case .moving(let strategy):
            switch strategy {
            case .rename: return "Déplacement…"
            case .dittoFallback: return "Copie (ditto)…"
            }
        case .recreatingVenv(let venv): return "Recréation du venv \(venv.lastPathComponent)…"
        case .reinstallingNodeModules: return "Réinstallation de node_modules…"
        case .creatingCompatibilitySymlink: return "Création du lien de compatibilité…"
        case .verifyingGitAfter: return "Vérification git (après)…"
        case .scanningResidualPaths: return "Analyse des chemins résiduels…"
        case .scanningSymlinks: return "Analyse des liens symboliques…"
        case .finished(let result):
            switch result.status {
            case .ok: return "Terminé"
            case .warning: return "Terminé avec avertissements"
            case .critical: return "Critique — source préservée"
            case .failed: return "Échec : \(result.failureReason ?? "raison inconnue")"
            }
        }
    }
}
