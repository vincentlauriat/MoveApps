import Darwin
import Foundation
@testable import MoveAppsCore

// MARK: - Filesystem / git fixtures

enum Fixture {
    static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moveapps-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ contents: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func runGit(_ args: [String], in directory: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    /// Creates a real UNIX domain socket special file at `url` — the same file type `ditto`
    /// cannot duplicate, reproducing a stale `.git/fsmonitor--daemon.ipc` left behind by
    /// `core.fsmonitor`. `bind(2)` enforces a ~104-byte `sun_path` limit that the deep `/var/
    /// folders/.../moveapps-tests-<uuid>/...` fixture path would blow past, so the socket is
    /// bound at a short path under `/tmp` first, then moved into place with `rename`, which has
    /// no such limit.
    static func makeUnixSocket(at url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let shortPath = "/tmp/moveapps-test-sock-\(UUID().uuidString.prefix(8))"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(fd >= 0, "socket() failed: \(String(cString: strerror(errno)))")
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPath in
            let dest = rawPath.bindMemory(to: CChar.self)
            _ = shortPath.withCString { src in
                strncpy(dest.baseAddress, src, sunPathCapacity - 1)
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        precondition(bindResult == 0, "bind() failed: \(String(cString: strerror(errno)))")

        try? fm.removeItem(atPath: url.path)
        try? fm.moveItem(atPath: shortPath, toPath: url.path)
    }

    /// Creates a git repo with the given files, committed on a clean tree.
    static func makeCleanRepo(at repo: URL, files: [String: String]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: repo, withIntermediateDirectories: true)
        for (relative, content) in files {
            write(content, to: repo.appendingPathComponent(relative))
        }
        runGit(["init", "-q", "-b", "main"], in: repo)
        runGit(["config", "user.email", "test@example.com"], in: repo)
        runGit(["config", "user.name", "MoveApps Test"], in: repo)
        runGit(["config", "commit.gpgsign", "false"], in: repo)
        runGit(["add", "-A"], in: repo)
        runGit(["commit", "-q", "-m", "init"], in: repo)
    }
}

// MARK: - Test doubles

/// A `DirectoryCopying` that copies faithfully, then optionally corrupts the copy:
///  - `drop`: deletes a tracked file from the destination (and, when `compensateCount`,
///    adds an untracked `.DS_Store` so the file count still matches — this reproduces the
///    `onyx` production bug where counting alone missed the loss).
///  - `modify`: appends to a tracked file so git sees a benign modification.
struct FaultInjectingCopier: DirectoryCopying {
    var drop: String? = nil
    var modify: String? = nil
    var compensateCount: Bool = true

    func copy(from source: URL, to destination: URL) async -> Bool {
        let fm = FileManager.default
        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            return false
        }
        if let drop {
            try? fm.removeItem(at: destination.appendingPathComponent(drop))
            if compensateCount {
                fm.createFile(
                    atPath: destination.appendingPathComponent(".DS_Store").path,
                    contents: Data("filler".utf8)
                )
            }
        }
        if let modify {
            let target = destination.appendingPathComponent(modify)
            if let handle = try? FileHandle(forWritingTo: target) {
                handle.seekToEndOfFile()
                handle.write(Data("\n# mutated by test\n".utf8))
                try? handle.close()
            }
        }
        return true
    }
}

/// An `InitScriptRunning` that records its invocations and returns a chosen exit code, so tests
/// can assert the init script was (or wasn't) run and with which arguments — without executing a
/// real shell script.
actor StubInitScriptRunner: InitScriptRunning {
    struct Call: Sendable, Hashable {
        let directory: URL
        let displayName: String
        let slug: String
    }

    private(set) var calls: [Call] = []
    private let exitCode: Int32

    init(exitCode: Int32 = 0) {
        self.exitCode = exitCode
    }

    func run(in directory: URL, displayName: String, slug: String) async -> ProcessResult {
        calls.append(Call(directory: directory, displayName: displayName, slug: slug))
        return ProcessResult(exitCode: exitCode, standardOutput: "", standardError: "", timedOut: false)
    }
}

/// An `ICloudMaterializing` that never resolves; used to prove callers stay bounded.
struct NeverResolvingMaterializer: ICloudMaterializing {
    let attempts: Int

    func materialize(at directory: URL, onProgress: @Sendable (MaterializationProgress) -> Void) async {
        for attempt in 1...max(1, attempts) {
            onProgress(MaterializationProgress(
                remaining: 1,
                total: 1,
                elapsed: .seconds(attempt),
                limit: .seconds(attempts),
                isFinal: attempt == attempts
            ))
        }
    }
}

/// Thread-safe recorder for progress callbacks fired from `@Sendable` closures.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MaterializationProgress] = []

    func record(_ value: MaterializationProgress) {
        lock.lock(); storage.append(value); lock.unlock()
    }

    var reports: [MaterializationProgress] {
        lock.lock(); defer { lock.unlock() }; return storage
    }

    /// Just the remaining counts, in order.
    var values: [Int] { reports.map(\.remaining) }
}

// MARK: - Pipeline helpers

extension TransferPipeline {
    /// Runs the plan and returns the final `TransferResult`.
    func finalResult(for plan: TransferPlan) async -> TransferResult? {
        var result: TransferResult?
        for await step in run(plan) {
            if case .finished(let r) = step { result = r }
        }
        return result
    }
}
