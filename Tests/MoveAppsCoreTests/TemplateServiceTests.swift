import Foundation
import Testing
@testable import MoveAppsCore

@Suite("TemplateService")
struct TemplateServiceTests {
    @Test("lists direct subfolders as templates, sorted, ignoring loose files")
    func listsTemplates() {
        let root = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        Fixture.write("x", to: root.appendingPathComponent("SwiftApp/README.md"))
        Fixture.write("x", to: root.appendingPathComponent("PythonScript/main.py"))
        Fixture.write("loose", to: root.appendingPathComponent("notes.txt"))

        let templates = TemplateService().templates(in: root)
        #expect(templates.map(\.name) == ["PythonScript", "SwiftApp"])
    }

    @Test("missing templates root yields an empty list, not a crash")
    func missingRoot() {
        let root = Fixture.makeTempDir().appendingPathComponent("does-not-exist")
        #expect(TemplateService().templates(in: root).isEmpty)
    }

    @Test("creates a project by copying the template and running git init")
    func createsProjectWithGit() async {
        let base = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let templatesRoot = base.appendingPathComponent("templates")
        let destinationRoot = base.appendingPathComponent("active")
        Fixture.write("# seed", to: templatesRoot.appendingPathComponent("SwiftApp/README.md"))

        let template = TemplateService().templates(in: templatesRoot).first!
        let result = await TemplateService().createProject(
            named: "MyNewApp",
            from: template,
            destinationRoot: destinationRoot,
            gitInit: true
        )

        guard case .created(let url, let gitInitialized, let initScript) = result else {
            Issue.record("expected .created, got \(result)")
            return
        }
        #expect(url == destinationRoot.appendingPathComponent("MyNewApp"))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("README.md").path))
        #expect(gitInitialized)
        #expect(initScript == .none)   // this template ships no bootstrap.sh
        #expect(await GitService().isRepository(url))
    }

    // MARK: - Init script

    /// Builds a templates root containing one template that ships a `Scripts/bootstrap.sh`.
    private func templateWithScript(named name: String = "SwiftApp") -> (root: URL, cleanup: () -> Void) {
        let base = Fixture.makeTempDir()
        let templatesRoot = base.appendingPathComponent("templates")
        Fixture.write("# seed", to: templatesRoot.appendingPathComponent("\(name)/README.md"))
        Fixture.write("#!/usr/bin/env bash\nexit 0\n",
                      to: templatesRoot.appendingPathComponent("\(name)/\(templateInitScriptRelativePath)"))
        return (templatesRoot, { try? FileManager.default.removeItem(at: base) })
    }

    @Test("runs the init script when the template ships one and the caller opts in")
    func runsInitScript() async {
        let (templatesRoot, cleanup) = templateWithScript()
        defer { cleanup() }
        let destinationRoot = templatesRoot.deletingLastPathComponent().appendingPathComponent("active")
        let stub = StubInitScriptRunner()

        let template = TemplateService().templates(in: templatesRoot).first!
        let result = await TemplateService(scriptRunner: stub).createProject(
            named: "My New App",
            from: template,
            destinationRoot: destinationRoot,
            gitInit: false,
            runInitScript: true
        )

        guard case .created(_, _, let initScript) = result else {
            Issue.record("expected .created, got \(result)")
            return
        }
        #expect(initScript == .ran)
        let calls = await stub.calls
        #expect(calls.count == 1)
        #expect(calls.first?.displayName == "My New App")
        #expect(calls.first?.slug == "MyNewApp")   // spaces stripped
        #expect(calls.first?.directory == destinationRoot.appendingPathComponent("My New App"))
    }

    @Test("does not run the init script when the caller opts out")
    func skipsInitScript() async {
        let (templatesRoot, cleanup) = templateWithScript()
        defer { cleanup() }
        let destinationRoot = templatesRoot.deletingLastPathComponent().appendingPathComponent("active")
        let stub = StubInitScriptRunner()

        let template = TemplateService().templates(in: templatesRoot).first!
        let result = await TemplateService(scriptRunner: stub).createProject(
            named: "MyNewApp",
            from: template,
            destinationRoot: destinationRoot,
            gitInit: false,
            runInitScript: false
        )

        guard case .created(_, _, let initScript) = result else {
            Issue.record("expected .created, got \(result)")
            return
        }
        #expect(initScript == .skipped)
        #expect(await stub.calls.isEmpty)
    }

    @Test("reports .failed when the init script exits non-zero")
    func reportsFailedScript() async {
        let (templatesRoot, cleanup) = templateWithScript()
        defer { cleanup() }
        let destinationRoot = templatesRoot.deletingLastPathComponent().appendingPathComponent("active")
        let stub = StubInitScriptRunner(exitCode: 1)

        let template = TemplateService().templates(in: templatesRoot).first!
        let result = await TemplateService(scriptRunner: stub).createProject(
            named: "MyNewApp",
            from: template,
            destinationRoot: destinationRoot,
            gitInit: false,
            runInitScript: true
        )

        guard case .created(_, _, let initScript) = result else {
            Issue.record("expected .created, got \(result)")
            return
        }
        #expect(initScript == .failed)
        // The copy is still on disk even though the script failed.
        #expect(FileManager.default.fileExists(atPath: destinationRoot.appendingPathComponent("MyNewApp").path))
    }

    @Test("refuses to overwrite an existing destination")
    func refusesExistingDestination() async {
        let base = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let templatesRoot = base.appendingPathComponent("templates")
        let destinationRoot = base.appendingPathComponent("active")
        Fixture.write("# seed", to: templatesRoot.appendingPathComponent("SwiftApp/README.md"))
        Fixture.write("existing", to: destinationRoot.appendingPathComponent("MyNewApp/keep.txt"))

        let template = TemplateService().templates(in: templatesRoot).first!
        let result = await TemplateService().createProject(
            named: "MyNewApp",
            from: template,
            destinationRoot: destinationRoot,
            gitInit: false
        )
        guard case .destinationExists = result else {
            Issue.record("expected .destinationExists, got \(result)")
            return
        }
        // The pre-existing file must be untouched.
        #expect(FileManager.default.fileExists(atPath: destinationRoot.appendingPathComponent("MyNewApp/keep.txt").path))
    }

    @Test("rejects an empty or path-bearing name")
    func rejectsInvalidName() async {
        let base = Fixture.makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let templatesRoot = base.appendingPathComponent("templates")
        Fixture.write("# seed", to: templatesRoot.appendingPathComponent("SwiftApp/README.md"))
        let template = TemplateService().templates(in: templatesRoot).first!

        for bad in ["", "   ", "sub/dir"] {
            let result = await TemplateService().createProject(
                named: bad,
                from: template,
                destinationRoot: base.appendingPathComponent("active"),
                gitInit: false
            )
            #expect(result == .invalidName)
        }
    }
}
