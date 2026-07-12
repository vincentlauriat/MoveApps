import Foundation

/// A trace left in the shared Archive when a project is checked out onto one Mac: which host took
/// it, on which day, and (as best-effort enhancements) where it landed and how big it was. The
/// host and day are always known from the marker's *filename*; `destinationPath`/`sizeBytes` come
/// from the marker's JSON body, which may not be materialized yet on an iCloud-evicted placeholder.
public struct CheckoutReference: Sendable, Hashable, Codable {
    public let hostName: String
    public let takenAt: Date
    public let destinationPath: String?
    public let sizeBytes: Int64?

    public init(
        hostName: String,
        takenAt: Date,
        destinationPath: String? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.hostName = hostName
        self.takenAt = takenAt
        self.destinationPath = destinationPath
        self.sizeBytes = sizeBytes
    }
}
