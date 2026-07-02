import Foundation

/// Outcome of a completed (or failed) transfer.
public struct TransferResult: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Codable {
        case ok
        case warning
        case critical
        case failed
    }

    public let status: Status
    public let warnings: [TransferWarning]
    /// Whether the source directory was removed. Always `false` when `status == .critical`
    /// or `.failed` — the source is preserved for inspection.
    public let sourceDeleted: Bool
    public let destinationURL: URL?
    public let failureReason: String?

    public init(
        status: Status,
        warnings: [TransferWarning],
        sourceDeleted: Bool,
        destinationURL: URL?,
        failureReason: String? = nil
    ) {
        self.status = status
        self.warnings = warnings
        self.sourceDeleted = sourceDeleted
        self.destinationURL = destinationURL
        self.failureReason = failureReason
    }

    /// Derives the status from the collected warnings (critical wins over warning over ok).
    static func make(warnings: [TransferWarning], sourceDeleted: Bool, destinationURL: URL?) -> TransferResult {
        let status: Status
        if warnings.contains(where: { $0.isCritical }) {
            status = .critical
        } else if warnings.isEmpty {
            status = .ok
        } else {
            status = .warning
        }
        return TransferResult(status: status, warnings: warnings, sourceDeleted: sourceDeleted, destinationURL: destinationURL)
    }

    static func failed(reason: String, destinationURL: URL? = nil, warnings: [TransferWarning] = []) -> TransferResult {
        TransferResult(status: .failed, warnings: warnings, sourceDeleted: false,
                       destinationURL: destinationURL, failureReason: reason)
    }
}
