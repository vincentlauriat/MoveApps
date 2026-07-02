import Foundation

/// A detected Python virtual environment and its captured package list (`pip freeze`).
public struct VenvInfo: Sendable, Hashable, Codable {
    public let path: URL
    public let packages: [String]

    public init(path: URL, packages: [String]) {
        self.path = path
        self.packages = packages
    }
}
