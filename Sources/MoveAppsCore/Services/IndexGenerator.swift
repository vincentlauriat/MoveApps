import Foundation

/// Outcome of writing the index to disk.
public enum IndexGenerationResult: Sendable, Equatable {
    /// The index was written to these URLs (one per root).
    case written([URL])
    /// Writing failed with this human-readable reason.
    case failed(String)
}

/// Builds a unified Markdown index of every project across both roots (Active + Archive) and
/// writes an identical copy into each root (`<active>/INDEX.md` and `<archive>/INDEX.md`).
///
/// Everything here is pure filesystem work (scan + read README + write), so the type is a plain
/// `Sendable` struct with synchronous methods — callers wrap it in `Task.detached` to keep the
/// scan off the main actor, exactly like `ProjectListing.scanSync` does for the project lists.
///
/// Per-project descriptions are extracted from each project's `README.md` (first meaningful prose
/// line) — the app can't author prose itself, so this is the realistic source. Per-project disk
/// size is deliberately omitted: measuring it means one `du` per project (~90 of them), which is
/// far too slow for a "regenerate on every transfer" action, and the scan already gives stack tags
/// and category folders for free.
public struct IndexGenerator: Sendable {
    private let scanner: ProjectScanner
    private var fileManager: FileManager { .default }

    public init(scanner: ProjectScanner = ProjectScanner()) {
        self.scanner = scanner
    }

    // MARK: - Public API

    /// Generates the index and writes an identical copy to each root. Returns `.written` with the
    /// URLs on success, or `.failed` on the first write error (a missing root is skipped, not an
    /// error — the other copy is still written).
    @discardableResult
    public func write(roots: RootLocations, now: Date = Date()) -> IndexGenerationResult {
        let markdown = makeMarkdown(roots: roots, now: now)
        var written: [URL] = []
        for root in [roots.active, roots.archive] {
            // Skip a root that isn't mounted/present rather than failing the whole run — one Mac
            // may not have both roots materialized at once.
            guard fileManager.fileExists(atPath: root.path) else { continue }
            let url = root.appendingPathComponent("INDEX.md", isDirectory: false)
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                written.append(url)
            } catch {
                return .failed("Échec d'écriture de \(url.path) : \(error.localizedDescription)")
            }
        }
        return .written(written)
    }

    /// Builds the full Markdown document covering both roots. Exposed separately so tests can
    /// assert on the content without touching the real roots.
    public func makeMarkdown(roots: RootLocations, now: Date = Date()) -> String {
        let active = scanner.scan(roots.active).sorted(by: Self.byName)
        let archive = scanner.scan(roots.archive).sorted(by: Self.byName)

        var out = ""
        out += "# Index des projets\n\n"
        let total = active.count + archive.count
        out += "_\(total) projet\(plural(total)) · \(active.count) actif\(plural(active.count)) · "
        out += "\(archive.count) archivé\(plural(archive.count)) · "
        out += "Généré le \(Self.dateString(now)) par MoveApps.app_\n\n"
        out += "Deux racines : **Actif** (`\(displayPath(roots.active))`, local) et "
        out += "**Archive** (`\(displayPath(roots.archive))`, iCloud). "
        out += "Copie identique dans chacune. Chaque entrée : **nom** — `chemin` — stack — "
        out += "description (extraite du README).\n\n"
        out += "---\n\n"

        out += section(title: "🟢 Actif", subtitle: displayPath(roots.active), projects: active)
        out += section(title: "📦 Archive", subtitle: displayPath(roots.archive), projects: archive)

        out += "---\n\n"
        out += "*Index généré automatiquement par MoveApps.app "
        out += "(scan des deux racines + extraction des README). "
        out += "Se régénère à chaque transfert et via le bouton du tableau de bord.*\n"
        return out
    }

    // MARK: - Rendering

    /// One root's section: category folders first (sorted), then loose root-level projects.
    private func section(title: String, subtitle: String, projects: [ProjectCandidate]) -> String {
        var out = "## \(title) — `\(subtitle)` (\(projects.count) projet\(plural(projects.count)))\n\n"
        if projects.isEmpty {
            out += "_Aucun projet._\n\n"
            return out
        }

        // Group by container folder; nil container = loose at the root.
        var byContainer: [String: [ProjectCandidate]] = [:]
        var loose: [ProjectCandidate] = []
        for project in projects {
            if let container = project.containerName {
                byContainer[container, default: []].append(project)
            } else {
                loose.append(project)
            }
        }

        for container in byContainer.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            out += "### \(container)/\n\n"
            for project in (byContainer[container] ?? []).sorted(by: Self.byName) {
                out += line(for: project, container: container)
            }
            out += "\n"
        }

        if !loose.isEmpty {
            out += "### Racine\n\n"
            for project in loose.sorted(by: Self.byName) {
                out += line(for: project, container: nil)
            }
            out += "\n"
        }
        return out
    }

    private func line(for project: ProjectCandidate, container: String?) -> String {
        let relative = container.map { "\($0)/\(project.name)" } ?? project.name
        var line = "- **\(project.name)** — `\(relative)`"
        let stack = stackLabel(project.stackTags)
        if !stack.isEmpty { line += " — \(stack)" }
        if let description = description(for: project) { line += " — \(description)" }
        line += "\n"
        return line
    }

    // MARK: - Stack labels

    /// Human-readable, deterministically-ordered stack tags (git last — it's near-ubiquitous).
    private func stackLabel(_ tags: Set<StackTag>) -> String {
        let order: [StackTag] = [.xcode, .node, .python, .rust, .go, .git]
        let names: [StackTag: String] = [
            .git: "git", .node: "Node", .python: "Python",
            .xcode: "Xcode", .rust: "Rust", .go: "Go",
        ]
        return order.filter { tags.contains($0) }.compactMap { names[$0] }.joined(separator: " · ")
    }

    // MARK: - README extraction

    private static let readmeNames = [
        "README.md", "README.fr.md", "Readme.md", "readme.md", "README.markdown", "README",
    ]

    /// First meaningful prose line of the project's README, cleaned of Markdown and truncated.
    /// Falls back to the README's H1 title when there's no prose (e.g. a heading-only stub).
    private func description(for project: ProjectCandidate) -> String? {
        for name in Self.readmeNames {
            let url = project.path.appendingPathComponent(name, isDirectory: false)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let line = Self.firstMeaningfulLine(content) { return line }
        }
        return nil
    }

    /// Scans README lines for the first line of real prose, skipping headings, badges, images,
    /// raw HTML, blockquotes, rules, table rows, ASCII art and multilingual nav bars. Remembers
    /// the first H1 as a fallback title.
    static func firstMeaningfulLine(_ content: String) -> String? {
        var fallbackTitle: String?
        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                if fallbackTitle == nil {
                    let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    let cleaned = cleanMarkdown(title)
                    // A title is a last-resort fallback, so it's held to a laxer bar than prose
                    // (single words are fine) — just non-empty and mostly letters, not ASCII art.
                    if !cleaned.isEmpty, cleaned.contains(where: { $0.isLetter }) { fallbackTitle = cleaned }
                }
                continue
            }
            // Blockquotes / tables / rules / images / badges — never a description.
            if line.hasPrefix(">") || line.hasPrefix("|") { continue }
            if line == "---" || line == "***" || line == "___" { continue }
            if line.hasPrefix("![") || line.hasPrefix("[![") { continue }
            if line.contains("shields.io") || line.contains("img.shields") { continue }
            // Raw HTML lines/fragments (`<div>`, `…</p>`, `<br/>`) and stray tag attributes
            // (`src="…"`, `media="…"`, `alt="…"`) — any `="` is attribute soup, never prose.
            if line.hasPrefix("<") || line.contains("</") || line.contains("/>")
                || line.contains("=\"") { continue }
            // Multilingual nav / link bars ("English | 한국어 | 中文 | …").
            if line.components(separatedBy: "|").count >= 3 { continue }
            // Label lines ("macOS / Linux:", "## Install:").
            if line.hasSuffix(":") { continue }
            // Shell command / install snippets ("curl … | bash", "npm install …").
            if startsWithCommand(line) { continue }
            // A line that is *only* a markdown link/badge (e.g. "[🇬🇧 English](README.fr.md)").
            if line.hasPrefix("[") && line.hasSuffix(")") && !line.contains(" ") { continue }

            let cleaned = cleanMarkdown(line)
            // A label line ("macOS / Linux:") whose colon was hidden behind emphasis markers.
            if cleaned.hasSuffix(":") { continue }
            if isProse(cleaned) { return truncate(cleaned) }
        }
        return fallbackTitle.map { truncate($0) }
    }

    private static let commandPrefixes: Set<String> = [
        "curl", "wget", "npm", "npx", "pnpm", "yarn", "bun", "git", "brew", "sudo",
        "bash", "sh", "cd", "docker", "cargo", "pip", "pip3", "python", "python3",
        "node", "make", "xcodebuild", "swift", "go", "$",
        "irm", "iex", "powershell", "export", "source", "chmod", "mkdir",
    ]

    /// Whether the line reads as a shell command / install snippet rather than prose.
    static func startsWithCommand(_ line: String) -> Bool {
        if line.hasPrefix("./") || line.hasPrefix("$ ") { return true }
        let firstToken = line.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
        return commandPrefixes.contains(firstToken)
    }

    /// A cleaned line reads as a real sentence — long enough, contains a space, and is mostly
    /// letters (filters ASCII-art banners and box-drawing separators that survive Markdown stripping).
    static func isProse(_ text: String) -> Bool {
        guard text.count >= 12, text.contains(" ") else { return false }
        let nonSpace = text.filter { !$0.isWhitespace }
        guard !nonSpace.isEmpty else { return false }
        let letters = nonSpace.filter { $0.isLetter }.count
        return Double(letters) / Double(nonSpace.count) >= 0.55
    }

    /// Strips the common inline Markdown and HTML entities so a README line reads as plain prose.
    static func cleanMarkdown(_ text: String) -> String {
        var s = text
        // Links / images: [text](url) -> text, ![alt](url) -> alt.
        s = s.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Residual HTML tags.
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Common HTML entities.
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&rsquo;": "'"]
        for (entity, replacement) in entities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        // Emphasis / code markers.
        for marker in ["**", "__", "*", "`", "~~"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        // Collapse runs of whitespace.
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Truncates a description to a readable length, cutting on a word boundary.
    static func truncate(_ text: String, limit: Int = 180) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return prefix[..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
        }
        return prefix + "…"
    }

    // MARK: - Helpers

    private static func byName(_ a: ProjectCandidate, _ b: ProjectCandidate) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private func plural(_ n: Int) -> String { n == 1 ? "" : "s" }

    /// A `~`-abbreviated path for display (`/Users/x/DevApps` -> `~/DevApps`).
    private func displayPath(_ url: URL) -> String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
