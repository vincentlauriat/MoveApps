import Foundation
import Observation
import MoveAppsCore

/// Drives the menu-bar dashboard: at-a-glance stats about both roots (project counts, disk
/// usage, last transfer) plus the "new project from template" action. It never runs transfers —
/// those live in the main window now — so it holds no transfer pipeline state.
@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var activeCount = 0
    public private(set) var archiveCount = 0
    public private(set) var isScanning = false

    public private(set) var activeSizeBytes: Int64?
    public private(set) var archiveSizeBytes: Int64?
    public private(set) var isMeasuringDisk = false

    public private(set) var lastTransfer: TransferRecord?

    public private(set) var templates: [ProjectTemplate] = []

    /// Set while a project is being created, and cleared with the outcome for the sheet to show.
    public private(set) var isCreating = false
    public private(set) var lastCreation: ProjectCreationResult?

    private let rootPaths: RootPathsController
    /// Read-only view of the same history file the main window writes to. Safe as a second
    /// instance because the dashboard only ever calls `all()` (no concurrent `append`).
    private let historyStore: TransferHistoryStore
    private let diskUsage = DiskUsage()
    private let templateService = TemplateService()

    public init(rootPaths: RootPathsController) {
        self.rootPaths = rootPaths
        self.historyStore = TransferHistoryStore(fileURL: MainWindowViewModel.defaultHistoryURL())
    }

    public var templatesConfigured: Bool { !templates.isEmpty }

    /// Refreshes counts, last transfer and template list quickly; kicks off the slower disk
    /// measurement separately so the fast stats aren't held up behind `du`.
    public func refresh() {
        let locations = rootPaths.settings.locations
        let templatesRoot = rootPaths.settings.templatesURL
        isScanning = true

        Task {
            let scanned = await Task.detached { ProjectListing.scanSync(locations) }.value
            self.activeCount = scanned.filter { $0.root == .active }.count
            self.archiveCount = scanned.filter { $0.root == .archive }.count
            self.isScanning = false
        }

        Task {
            let all = await historyStore.all()
            self.lastTransfer = all.last
        }

        templates = templateService.templates(in: templatesRoot)

        measureDisk()
    }

    /// Reloads just the template list (e.g. after the user points Settings at a new folder).
    public func reloadTemplates() {
        templates = templateService.templates(in: rootPaths.settings.templatesURL)
    }

    private func measureDisk() {
        let locations = rootPaths.settings.locations
        isMeasuringDisk = true
        Task {
            async let active = diskUsage.sizeBytes(of: locations.active)
            async let archive = diskUsage.sizeBytes(of: locations.archive)
            let (a, r) = await (active, archive)
            self.activeSizeBytes = a
            self.archiveSizeBytes = r
            self.isMeasuringDisk = false
        }
    }

    // MARK: - New project

    public func createProject(named name: String, from template: ProjectTemplate, gitInit: Bool) {
        guard !isCreating else { return }
        isCreating = true
        lastCreation = nil
        let destinationRoot = rootPaths.settings.locations.active

        Task {
            let result = await templateService.createProject(
                named: name,
                from: template,
                destinationRoot: destinationRoot,
                gitInit: gitInit
            )
            self.lastCreation = result
            self.isCreating = false
            if case .created = result { self.refresh() }
        }
    }

    public func clearCreationResult() {
        lastCreation = nil
    }
}
