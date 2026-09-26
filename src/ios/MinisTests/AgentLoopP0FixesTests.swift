import CryptoKit
import XCTest
@testable import Minis

/// Unit tests for the V3 P0 agent-loop fixes. Each section pins the pure
/// decision core of one fix; the batch dispatcher, file tools and stop path
/// delegate to these helpers so the contracts below are the contracts that
/// ship.
final class AgentLoopP0FixesTests: XCTestCase {

    // MARK: - P0-1: value-mutating repairs on high-risk write fields

    private var writeTools: [AgentToolDefinition] {
        [
            AgentToolDefinition(
                name: "file_write",
                description: "Write a file",
                parameters: [
                    "path": AgentToolParam(type: .string, description: "File path"),
                    "content": AgentToolParam(type: .string, description: "File content"),
                ],
                required: ["path", "content"]
            ),
            AgentToolDefinition(
                name: "file_edit",
                description: "Edit a file",
                parameters: [
                    "path": AgentToolParam(type: .string, description: "File path"),
                    "old_string": AgentToolParam(type: .string, description: "Text to replace"),
                    "new_string": AgentToolParam(type: .string, description: "Replacement"),
                ],
                required: ["path", "old_string", "new_string"]
            ),
            AgentToolDefinition(
                name: "file_read",
                description: "Read a file",
                parameters: [
                    "path": AgentToolParam(type: .string, description: "File path"),
                ],
                required: ["path"]
            ),
        ]
    }

    /// End-to-end through repairToolArgs: a coerced `path: 123` must produce
    /// a type-coerce repair tag that highRiskMutationTag flags for refusal.
    func testP01_fileWrite_pathCoerced_isIntercepted() {
        let outcome = AIChatViewModel.repairToolArgs(
            name: "file_write",
            args: ["path": 123, "content": "hello"],
            rawTail: nil,
            tools: writeTools
        )
        XCTAssertTrue(outcome.repairs.contains("type-coerce:path"))
        let tag = AIChatViewModel.highRiskMutationTag(toolName: "file_write", repairs: outcome.repairs)
        XCTAssertEqual(tag, "type-coerce:path", "coerced path on file_write must refuse execution")
    }

    func testP01_fileWrite_contentCoerced_isIntercepted() {
        let outcome = AIChatViewModel.repairToolArgs(
            name: "file_write",
            args: ["path": "/a.txt", "content": true],
            rawTail: nil,
            tools: writeTools
        )
        XCTAssertTrue(outcome.repairs.contains("type-coerce:content"))
        XCTAssertNotNil(AIChatViewModel.highRiskMutationTag(toolName: "file_write", repairs: outcome.repairs))
    }

    func testP01_fileEdit_oldStringCoerced_isIntercepted() {
        let outcome = AIChatViewModel.repairToolArgs(
            name: "file_edit",
            args: ["path": "/a.txt", "old_string": 0, "new_string": "x"],
            rawTail: nil,
            tools: writeTools
        )
        XCTAssertTrue(outcome.repairs.contains("type-coerce:old_string"))
        XCTAssertNotNil(AIChatViewModel.highRiskMutationTag(toolName: "file_edit", repairs: outcome.repairs))
    }

    func testP01_toolTitleCoerced_isAllowed() {
        // tool_title is not a high-risk field: coercion stays allowed.
        XCTAssertNil(AIChatViewModel.highRiskMutationTag(
            toolName: "file_write", repairs: ["type-coerce:tool_title"]))
    }

    func testP01_fuzzyRename_isAllowed() {
        // End-to-end: `contents` → `content` is a key-only rename (value
        // intact), so it must NOT be intercepted — it gets a hint instead.
        let outcome = AIChatViewModel.repairToolArgs(
            name: "file_write",
            args: ["path": "/a.txt", "contents": "hello"],
            rawTail: nil,
            tools: writeTools
        )
        XCTAssertTrue(outcome.repairs.contains("fuzzy:contents->content"))
        XCTAssertNil(AIChatViewModel.highRiskMutationTag(toolName: "file_write", repairs: outcome.repairs))
        XCTAssertEqual(AIChatViewModel.repairTagField("fuzzy:contents->content"), "content")
    }

    func testP01_truncation_notInterceptedByHighRiskBranch() {
        // truncation+ is whole-args reconstruction handled by its own
        // refusal branch — the high-risk branch must leave it alone.
        XCTAssertNil(AIChatViewModel.highRiskMutationTag(
            toolName: "file_write", repairs: ["truncation+}}"]))
        XCTAssertNil(AIChatViewModel.repairTagField("truncation+}}"))
    }

    func testP01_fileRead_coerceNotIntercepted() {
        // file_read is not a write tool: no high-risk fields at all.
        XCTAssertNil(AIChatViewModel.highRiskMutationTag(
            toolName: "file_read", repairs: ["type-coerce:path"]))
        XCTAssertNil(AIChatViewModel.highRiskMutationTag(
            toolName: "no_such_tool", repairs: ["type-coerce:path"]))
    }

    func testP01_repairTagField_parsing() {
        XCTAssertEqual(AIChatViewModel.repairTagField("type-coerce:path"), "path")
        XCTAssertEqual(AIChatViewModel.repairTagField("null-strip:content"), "content")
        XCTAssertEqual(AIChatViewModel.repairTagField("fuzzy:comand->command"), "command")
        XCTAssertNil(AIChatViewModel.repairTagField("truncation+noop"))
    }

    // MARK: - P0-3: batch-internal loop-detector counting

    func testP03_batchGate_firstTwoAllowed() {
        XCTAssertTrue(AIChatViewModel.batchGateAllowsExecution(seenCount: 0))
        XCTAssertTrue(AIChatViewModel.batchGateAllowsExecution(seenCount: 1))
    }

    func testP03_batchGate_thirdAndOnBlocked() {
        XCTAssertFalse(AIChatViewModel.batchGateAllowsExecution(seenCount: 2))
        XCTAssertFalse(AIChatViewModel.batchGateAllowsExecution(seenCount: 3))
        XCTAssertFalse(AIChatViewModel.batchGateAllowsExecution(seenCount: 10))
    }

    func testP03_batchKey_sharesDetectorHash() {
        // The batch gate keys on the same argsHashFor the cross-turn
        // detector uses, so "identical" means the same thing in both.
        let detector = ToolLoopDetector()
        let params: [String: Any] = ["path": "/tmp/foo", "offset": 1]
        let h1 = detector.argsHashFor("file_read", params)
        let h2 = detector.argsHashFor("file_read", params)
        XCTAssertEqual(h1, h2, "same (tool, args) must hash identically")
        XCTAssertNotEqual(h1, detector.argsHashFor("file_read", ["path": "/tmp/bar"]),
                          "different args must not collide")
        XCTAssertNotEqual(h1, detector.argsHashFor("shell_execute", params),
                          "different tools must not collide")
    }

    // MARK: - P0-4: cross-turn file baseline

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testP04_noBaseline_allows() {
        let mismatch = AIChatViewModel.fileBaselineMismatch(
            baseline: [:], hostPath: "/host/a.txt", currentData: Data("v1".utf8))
        XCTAssertNil(mismatch, "no baseline must never block a first-time edit")
    }

    func testP04_matchingBaseline_allows() {
        let data = Data("hello world".utf8)
        let mismatch = AIChatViewModel.fileBaselineMismatch(
            baseline: ["/host/a.txt": sha256Hex(data)],
            hostPath: "/host/a.txt",
            currentData: data)
        XCTAssertNil(mismatch, "unchanged bytes must allow the edit")
    }

    func testP04_changedBytes_aborts() {
        // file_read → shell `sed -i` changes another region → file_edit
        // must abort instead of clobbering the external change.
        let mismatch = AIChatViewModel.fileBaselineMismatch(
            baseline: ["/host/a.txt": sha256Hex(Data("v1".utf8))],
            hostPath: "/host/a.txt",
            currentData: Data("v2-external-change".utf8))
        XCTAssertNotNil(mismatch)
        XCTAssertNotEqual(mismatch?.expected, mismatch?.actual)
    }

    func testP04_otherPathBaseline_allows() {
        // A baseline for a different path must not gate this edit.
        let mismatch = AIChatViewModel.fileBaselineMismatch(
            baseline: ["/host/other.txt": sha256Hex(Data("v1".utf8))],
            hostPath: "/host/a.txt",
            currentData: Data("v2".utf8))
        XCTAssertNil(mismatch)
    }

    // MARK: - P0-2: stop / cancel path

    func testP02_snapshotHasInflight_sessionScoped() {
        XCTAssertTrue(ISHExecutionCoordinator.snapshotHasInflight(["a": [42]], sessionId: "a"))
        XCTAssertFalse(ISHExecutionCoordinator.snapshotHasInflight(["a": [42]], sessionId: "b"),
                       "another session's pid must not count")
        XCTAssertFalse(ISHExecutionCoordinator.snapshotHasInflight(["a": []], sessionId: "a"),
                       "registered-but-pidless must not count as live")
        XCTAssertFalse(ISHExecutionCoordinator.snapshotHasInflight([:], sessionId: "a"))
    }

    func testP02_snapshotHasInflight_nilSessionIsAny() {
        XCTAssertTrue(ISHExecutionCoordinator.snapshotHasInflight(["a": [], "b": [7]], sessionId: nil))
        XCTAssertFalse(ISHExecutionCoordinator.snapshotHasInflight(["a": []], sessionId: nil))
        XCTAssertFalse(ISHExecutionCoordinator.snapshotHasInflight([:], sessionId: nil))
    }

    func testP02_hasInflight_idleIsFalse() {
        // No commands are running inside a unit test: the real static
        // snapshot must report idle, so an idle Stop can't arm the flag.
        XCTAssertFalse(ISHExecutionCoordinator.hasInflight(sessionId: "p0-test-idle-\(UUID().uuidString)"))
    }

    func testP02_shouldLateKillPid() {
        // Forked before the stop (5 < 6) but registered after → must kill.
        XCTAssertTrue(ISHExecutionCoordinator.shouldLateKillPid(pid: 42, forkGeneration: 5, currentGeneration: 6))
        // Forked at/after the stop → belongs to the new generation, keep.
        XCTAssertFalse(ISHExecutionCoordinator.shouldLateKillPid(pid: 42, forkGeneration: 6, currentGeneration: 6))
        XCTAssertFalse(ISHExecutionCoordinator.shouldLateKillPid(pid: 42, forkGeneration: 7, currentGeneration: 6))
        // Non-positive pids are never kill targets.
        XCTAssertFalse(ISHExecutionCoordinator.shouldLateKillPid(pid: 0, forkGeneration: 5, currentGeneration: 6))
        XCTAssertFalse(ISHExecutionCoordinator.shouldLateKillPid(pid: -1, forkGeneration: 5, currentGeneration: 6))
    }

    func testP02_stopGeneration_bumpsPerSession() {
        let sid = "p0-test-gen-\(UUID().uuidString)"
        let other = "p0-test-gen-\(UUID().uuidString)"
        XCTAssertEqual(ISHExecutionCoordinator.currentStopGeneration(sessionId: sid), 0)
        // Idle stop kills nothing but still bumps the generation (P0-2e).
        XCTAssertEqual(ISHExecutionCoordinator.stopAllNonisolated(sessionId: sid), 0)
        XCTAssertEqual(ISHExecutionCoordinator.currentStopGeneration(sessionId: sid), 1)
        XCTAssertEqual(ISHExecutionCoordinator.currentStopGeneration(sessionId: other), 0,
                       "generation is per-session: other sessions unaffected")
        // The nil form bumps every known session — kept for app-terminate
        // style callers; the VM never passes nil (P0-2c).
        XCTAssertEqual(ISHExecutionCoordinator.stopAllNonisolated(), 0)
        XCTAssertEqual(ISHExecutionCoordinator.currentStopGeneration(sessionId: sid), 2)
    }

    // MARK: - P0-2d: cancel pre-check flag

    func testP02d_cancelPreCheck_allSignals() {
        XCTAssertFalse(AIChatViewModel.shouldCancelBeforeToolStart(
            taskCancelled: false, userDidCancel: false, commandCancelledByUser: false))
        // The P0-2d case: Stop set commandCancelledByUser WITHOUT cancelling
        // the Task — a not-yet-started sibling must still short-circuit.
        XCTAssertTrue(AIChatViewModel.shouldCancelBeforeToolStart(
            taskCancelled: false, userDidCancel: false, commandCancelledByUser: true))
        XCTAssertTrue(AIChatViewModel.shouldCancelBeforeToolStart(
            taskCancelled: true, userDidCancel: false, commandCancelledByUser: false))
        XCTAssertTrue(AIChatViewModel.shouldCancelBeforeToolStart(
            taskCancelled: false, userDidCancel: true, commandCancelledByUser: false))
    }
}
