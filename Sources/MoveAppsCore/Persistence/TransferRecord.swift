import Foundation

/// A persisted record of a completed transfer, for the history view.
public struct TransferRecord: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let projectName: String
    public let from: RootKind
    public let to: RootKind
    public let sourcePath: URL
    public let destinationPath: URL?
    public let date: Date
    public let status: TransferResult.Status
    public let warnings: [TransferWarning]

    public init(
        id: UUID = UUID(),
        projectName: String,
        from: RootKind,
        to: RootKind,
        sourcePath: URL,
        destinationPath: URL?,
        date: Date = Date(),
        status: TransferResult.Status,
        warnings: [TransferWarning]
    ) {
        self.id = id
        self.projectName = projectName
        self.from = from
        self.to = to
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.date = date
        self.status = status
        self.warnings = warnings
    }

    public init(plan: TransferPlan, result: TransferResult, date: Date = Date()) {
        self.init(
            projectName: plan.project.name,
            from: plan.from,
            to: plan.to,
            sourcePath: plan.project.path,
            destinationPath: result.destinationURL,
            date: date,
            status: result.status,
            warnings: result.warnings
        )
    }
}
