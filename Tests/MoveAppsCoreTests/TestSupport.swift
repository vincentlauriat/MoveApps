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

/// An `ICloudMaterializing` that never resolves; used to prove callers stay bounded.
struct NeverResolvingMaterializer: ICloudMaterializing {
    let attempts: Int

    func materialize(at directory: URL, onProgress: @Sendable (Int) -> Void) async {
        for _ in 0..<attempts {
            onProgress(1)
        }
    }
}

/// Thread-safe recorder for progress callbacks fired from `@Sendable` closures.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func record(_ value: Int) {
        lock.lock(); storage.append(value); lock.unlock()
    }

    var values: [Int] {
        lock.lock(); defer { lock.unlock() }; return storage
    }
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
