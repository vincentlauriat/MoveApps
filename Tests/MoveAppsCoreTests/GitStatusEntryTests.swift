import Foundation
import Testing
@testable import MoveAppsCore

@Suite("GitStatusEntry.parse")
struct GitStatusEntryTests {
    @Test("parses staged, unstaged, untracked, deleted, and rename entries")
    func parsesPorcelain() {
        let porcelain = [
            "M  staged.txt",
            " M unstaged.txt",
            "?? untracked.txt",
            "D  deleted-staged.txt",
            " D deleted-worktree.txt",
            "R  old.txt -> new.txt",
        ].joined(separator: "\n")

        let entries = GitStatusEntry.parse(porcelain)
        #expect(entries.count == 6)

        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })

        #expect(byPath["staged.txt"]?.indexStatus == "M")
        #expect(byPath["staged.txt"]?.worktreeStatus == " ")
        #expect(byPath["staged.txt"]?.isDeleted == false)

        #expect(byPath["unstaged.txt"]?.indexStatus == " ")
        #expect(byPath["unstaged.txt"]?.worktreeStatus == "M")

        #expect(byPath["untracked.txt"]?.indexStatus == "?")
        #expect(byPath["untracked.txt"]?.isDeleted == false)

        #expect(byPath["deleted-staged.txt"]?.isDeleted == true)
        #expect(byPath["deleted-worktree.txt"]?.isDeleted == true)

        #expect(byPath["old.txt -> new.txt"]?.indexStatus == "R")
        #expect(byPath["old.txt -> new.txt"]?.isDeleted == false)
    }

    @Test("only deleted entries surface in the deleted set")
    func deletedFiltering() {
        let porcelain = [
            "M  a.txt",
            "D  gone.txt",
            "?? new.txt",
        ].joined(separator: "\n")
        let deleted = GitStatusEntry.parse(porcelain).filter { $0.isDeleted }.map { $0.path }
        #expect(deleted == ["gone.txt"])
    }

    @Test("empty output yields no entries")
    func emptyOutput() {
        #expect(GitStatusEntry.parse("").isEmpty)
        #expect(GitStatusEntry.parse("\n\n").isEmpty)
    }
}
