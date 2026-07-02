import Foundation

/// Thrown when a bounded async operation exceeds its deadline.
public struct TimeoutError: Error, Sendable {
    public init() {}
}

/// Bounds an async operation with a deadline, mirroring the bash `with_timeout` helper.
/// Cancels the losing branch so no work leaks past the deadline.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        let result = try await group.next()!
        return result
    }
}

extension Duration {
    /// The duration expressed as a floating-point number of seconds.
    var secondsDouble: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1_000_000_000_000_000_000
    }
}
