import Foundation
import Testing
@testable import MoveAppsCore

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("a SIGTERM-ignoring child is escalated to SIGKILL so the bounded call still returns")
    func killEscalationAfterTimeout() async {
        // A child that ignores SIGTERM and would otherwise sleep far past the timeout. `perl` runs
        // the sleep in-process (no grandchild holding the stdout pipe open), so SIGKILL releases the
        // pipe immediately and the reads EOF — exactly the pathological case fireTimeout must handle.
        let runner = ProcessRunner(killGracePeriod: .milliseconds(200))

        let start = ContinuousClock.now
        let result = await runner.run(
            ["-e", "$SIG{TERM} = 'IGNORE'; sleep 30;"],
            executable: "/usr/bin/perl",
            timeout: .milliseconds(300)
        )
        let elapsed = ContinuousClock.now - start

        #expect(result.timedOut)
        // Without the SIGKILL escalation this would only return when the 30s sleep ends. The tight
        // wall-clock bound is what discriminates the fix from the pre-existing SIGTERM-only path.
        #expect(elapsed < .seconds(10))
    }
}
