import Foundation
import Testing
@testable import MoveAppsCore

@Suite("IndexGenerator")
struct IndexGeneratorTests {
    @Test("writes an identical INDEX.md into both roots, covering projects across both")
    func writesToBothRoots() throws {
        let base = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let active = base.appendingPathComponent("DevApps", isDirectory: true)
        let archive = base.appendingPathComponent("GitHub", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: active, withIntermediateDirectories: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)

        // Active: a category folder holding one Swift project + one loose Node project at the root.
        try fm.createDirectory(at: active.appendingPathComponent("NetworkTools/WifiManager/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: active.appendingPathComponent("NetworkTools/WifiManager/WifiManager.xcodeproj"), withIntermediateDirectories: true)
        Fixture.write(
            "# WifiManager\n\nApp menubar pour monitorer la qualité WiFi en temps réel.\n",
            to: active.appendingPathComponent("NetworkTools/WifiManager/README.md")
        )
        Fixture.write("{}", to: active.appendingPathComponent("curl.md/package.json"))

        // Archive: one project that was moved out.
        try fm.createDirectory(at: archive.appendingPathComponent("OldProject/.git"), withIntermediateDirectories: true)

        let roots = RootLocations(active: active, archive: archive)
        let result = IndexGenerator().write(roots: roots)

        guard case .written(let urls) = result else {
            Issue.record("expected .written, got \(result)")
            return
        }
        #expect(urls.count == 2)

        let activeIndex = try String(contentsOf: active.appendingPathComponent("INDEX.md"), encoding: .utf8)
        let archiveIndex = try String(contentsOf: archive.appendingPathComponent("INDEX.md"), encoding: .utf8)

        // Identical copy in each root.
        #expect(activeIndex == archiveIndex)

        // Covers projects from both roots, its category, its extracted README description, and stack.
        #expect(activeIndex.contains("WifiManager"))
        #expect(activeIndex.contains("### NetworkTools/"))
        #expect(activeIndex.contains("App menubar pour monitorer la qualité WiFi"))
        #expect(activeIndex.contains("Xcode"))
        #expect(activeIndex.contains("curl.md"))
        #expect(activeIndex.contains("OldProject"))
        #expect(activeIndex.contains("🟢 Actif"))
        #expect(activeIndex.contains("📦 Archive"))
    }

    @Test("renders a size column when sizes are provided, omits it otherwise")
    func rendersSizeWhenProvided() throws {
        let base = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let active = base.appendingPathComponent("DevApps", isDirectory: true)
        let archive = base.appendingPathComponent("GitHub", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: active.appendingPathComponent("Solo/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)

        let roots = RootLocations(active: active, archive: archive)
        let generator = IndexGenerator()
        let solo = active.appendingPathComponent("Solo")

        // Without sizes: no size string.
        let plain = generator.makeMarkdown(roots: roots)
        #expect(plain.contains("Solo"))

        // With sizes: the formatted size appears on the project's line.
        let sized = generator.makeMarkdown(roots: roots, sizes: [solo.standardizedFileURL: 5 * 1024 * 1024])
        let expected = ByteFormat.string(5 * 1024 * 1024)
        #expect(sized.contains(expected))
        #expect(!plain.contains(expected))
    }

    @Test("README extraction skips headings, badges and HTML, keeping the first prose line")
    func extractsProseFromReadme() {
        let readme = """
        <div align="center">

        ![Banner](docs/banner.png)

        # StartAlice

        [![Latest release](https://img.shields.io/github/v/release/x/y)](https://example.com)

        **One-click updater & launcher for [OpenAlice](https://github.com/x).**
        """
        let line = IndexGenerator.firstMeaningfulLine(readme)
        #expect(line == "One-click updater & launcher for OpenAlice.")
    }

    @Test("falls back to the H1 title when the README has no prose")
    func fallsBackToTitle() {
        let readme = "# JustATitle\n\n## Section\n"
        #expect(IndexGenerator.firstMeaningfulLine(readme) == "JustATitle")
    }

    @Test("skips raw HTML fragments, ASCII-art banners and multilingual nav bars")
    func skipsNoiseLines() {
        // HTML attribute continuation line (the claude-mem case).
        let html = "# claude-mem\n\n  src=\"https://example.com/preview.gif\"\n\nA memory system for Claude Code.\n"
        #expect(IndexGenerator.firstMeaningfulLine(html) == "A memory system for Claude Code.")

        // ASCII-art banner (the headroom case) then real prose.
        let ascii = "# headroom\n\n██╗ ██╗███████╗ █████╗ ██████╗\n\nA context compression layer for AI agents.\n"
        #expect(IndexGenerator.firstMeaningfulLine(ascii) == "A context compression layer for AI agents.")

        // Multilingual nav bar (the oh-my-claudecode case) then prose.
        let nav = "# omc\n\nEnglish | 한국어 | 中文 | 日本語\n\nMulti-agent orchestration layer for Claude Code.\n"
        #expect(IndexGenerator.firstMeaningfulLine(nav) == "Multi-agent orchestration layer for Claude Code.")
    }

    @Test("decodes HTML entities in the kept description")
    func decodesEntities() {
        let readme = "# minutes\n\nOpen-source conversation memory &amp; search tool.\n"
        #expect(IndexGenerator.firstMeaningfulLine(readme) == "Open-source conversation memory & search tool.")
    }

    @Test("truncates long descriptions on a word boundary")
    func truncatesLongDescriptions() {
        let long = String(repeating: "mot ", count: 100)
        let result = IndexGenerator.truncate(long, limit: 20)
        #expect(result.count <= 21) // 20 + the ellipsis
        #expect(result.hasSuffix("…"))
    }
}
