import Foundation

/// Result of running an external process.
public struct ProcessResult: Sendable, Hashable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool

    public init(exitCode: Int32, standardOutput: String, standardError: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }

    public var didSucceed: Bool { exitCode == 0 && !timedOut }

    public var trimmedOutput: String {
        standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var outputLines: [String] {
        standardOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// Async wrapper around `Process`/`Pipe` with an optional bounded timeout.
/// Replaces the bash `with_timeout <cmd>` helper. All `Process`/`Pipe` handling is
/// confined to a single `@unchecked Sendable` worker so nothing non-Sendable crosses
/// a concurrency boundary under `SWIFT_STRICT_CONCURRENCY: complete`.
public actor ProcessRunner {
    public init() {}

    public func run(
        _ arguments: [String],
        executable: String,
        currentDirectory: URL? = nil,
        timeout: Duration? = nil
    ) async -> ProcessResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
            let worker = ProcessWorker(
                arguments: arguments,
                executable: executable,
                currentDirectory: currentDirectory,
                timeout: timeout
            )
            worker.start { result in
                continuation.resume(returning: result)
            }
        }
    }
}

private final class ProcessWorker: @unchecked Sendable {
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let arguments: [String]
    private let executable: String
    private let currentDirectory: URL?
    private let timeout: Duration?

    private var outData = Data()
    private var errData = Data()
    private var didTimeout = false

    init(arguments: [String], executable: String, currentDirectory: URL?, timeout: Duration?) {
        self.arguments = arguments
        self.executable = executable
        self.currentDirectory = currentDirectory
        self.timeout = timeout
    }

    func start(completion: @escaping @Sendable (ProcessResult) -> Void) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardOutput = outPipe
        process.standardError = errPipe

        let queue = DispatchQueue(label: "com.vincent.MoveAppsCore.ProcessRunner", attributes: .concurrent)
        let group = DispatchGroup()

        // Observe termination via the handler rather than `waitUntilExit()`: the latter spins
        // a private CFRunLoop that races with the concurrent pipe reads and can hang forever.
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            group.leave()
            completion(ProcessResult(exitCode: -1, standardOutput: "",
                                     standardError: String(describing: error), timedOut: false))
            return
        }

        group.enter()
        queue.async {
            let data = self.outPipe.fileHandleForReading.readDataToEndOfFile()
            self.outData = data
            group.leave()
        }
        group.enter()
        queue.async {
            let data = self.errPipe.fileHandleForReading.readDataToEndOfFile()
            self.errData = data
            group.leave()
        }

        let watchdog: DispatchWorkItem?
        if let timeout {
            let item = DispatchWorkItem { [weak self] in self?.fireTimeout() }
            queue.asyncAfter(deadline: .now() + timeout.secondsDouble, execute: item)
            watchdog = item
        } else {
            watchdog = nil
        }

        group.notify(queue: queue) {
            watchdog?.cancel()
            let result = ProcessResult(
                exitCode: self.process.terminationStatus,
                standardOutput: String(decoding: self.outData, as: UTF8.self),
                standardError: String(decoding: self.errData, as: UTF8.self),
                timedOut: self.didTimeout
            )
            completion(result)
        }
    }

    private func fireTimeout() {
        if process.isRunning {
            didTimeout = true
            process.terminate()
        }
    }
}
