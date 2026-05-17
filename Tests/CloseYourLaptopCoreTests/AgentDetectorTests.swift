import XCTest
@testable import CloseYourLaptopCore

final class AgentDetectorTests: XCTestCase {
    func testDetectsCodexExecutable() {
        let process = ProcessSnapshot(
            pid: 101,
            parentPID: 1,
            cpuPercent: 0.1,
            state: "S",
            command: "/opt/homebrew/bin/codex"
        )

        XCTAssertEqual(AgentDetector.kind(for: process), .codex)
    }

    func testDetectsClaudeCodeNodeProcess() {
        let process = ProcessSnapshot(
            pid: 202,
            parentPID: 1,
            cpuPercent: 0.1,
            state: "S",
            command: "/opt/homebrew/bin/node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        )

        XCTAssertEqual(AgentDetector.kind(for: process), .claude)
    }

    func testIgnoresIdleGuiAppsByDefault() {
        let claudeApp = ProcessSnapshot(
            pid: 303,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Claude.app/Contents/MacOS/Claude"
        )

        let codexApp = ProcessSnapshot(
            pid: 304,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )

        XCTAssertNil(AgentDetector.kind(for: claudeApp))
        XCTAssertNil(AgentDetector.kind(for: codexApp))
    }

    func testIgnoresCodexAppServerButAllowsCodexExecWork() {
        let appServer = ProcessSnapshot(
            pid: 305,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --listen stdio://"
        )
        let exec = ProcessSnapshot(
            pid: 306,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex exec --json --model gpt-5.5"
        )

        XCTAssertNil(AgentDetector.kind(for: appServer))
        XCTAssertEqual(AgentDetector.kind(for: exec), .codex)
    }

    func testDetectsBusyCodexGuiWorkerDescendant() {
        let codexApp = ProcessSnapshot(
            pid: 500,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )
        let appServer = ProcessSnapshot(
            pid: 501,
            parentPID: 500,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        )
        let idleShell = ProcessSnapshot(
            pid: 502,
            parentPID: 500,
            cpuPercent: 0,
            state: "S",
            command: "/bin/zsh"
        )
        let worker = ProcessSnapshot(
            pid: 503,
            parentPID: 501,
            cpuPercent: 3.5,
            state: "R",
            command: "/bin/ps"
        )

        let report = AgentDetector.report(from: [codexApp, appServer, idleShell, worker], selfPID: 999)

        XCTAssertTrue(report.isActive)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.sessions[0].kind, .codex)
        XCTAssertEqual(report.sessions[0].root.pid, 500)
        XCTAssertEqual(report.sessions[0].descendants.map(\.pid), [503])
    }

    func testIgnoresIdleCodexGuiFurniture() {
        let codexApp = ProcessSnapshot(
            pid: 510,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )
        let renderer = ProcessSnapshot(
            pid: 511,
            parentPID: 510,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Frameworks/Codex Helper (Renderer).app/Contents/MacOS/Codex Helper (Renderer) --type=renderer"
        )
        let appServer = ProcessSnapshot(
            pid: 512,
            parentPID: 510,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        )
        let shell = ProcessSnapshot(
            pid: 513,
            parentPID: 510,
            cpuPercent: 0,
            state: "S",
            command: "/bin/zsh"
        )
        let mcp = ProcessSnapshot(
            pid: 514,
            parentPID: 512,
            cpuPercent: 0,
            state: "S",
            command: "npm exec xcodebuildmcp@latest mcp"
        )

        let report = AgentDetector.report(from: [codexApp, renderer, appServer, shell, mcp], selfPID: 999)

        XCTAssertFalse(report.isActive)
    }

    func testIgnoresBusyCodexElectronInfrastructure() {
        let codexApp = ProcessSnapshot(
            pid: 530,
            parentPID: 1,
            cpuPercent: 0.6,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )
        let renderer = ProcessSnapshot(
            pid: 531,
            parentPID: 530,
            cpuPercent: 6.0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Frameworks/Codex Helper (Renderer).app/Contents/MacOS/Codex Helper (Renderer) --type=renderer"
        )
        let gpuHelper = ProcessSnapshot(
            pid: 532,
            parentPID: 530,
            cpuPercent: 4.0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Frameworks/Codex Helper (GPU).app/Contents/MacOS/Codex Helper (GPU) --type=gpu-process"
        )
        let utility = ProcessSnapshot(
            pid: 533,
            parentPID: 530,
            cpuPercent: 2.0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper --type=utility"
        )
        let crashpad = ProcessSnapshot(
            pid: 534,
            parentPID: 530,
            cpuPercent: 1.0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/Helpers/crashpad_handler"
        )
        let chronicle = ProcessSnapshot(
            pid: 535,
            parentPID: 530,
            cpuPercent: 3.0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex_chronicle --watch"
        )
        let nodeRepl = ProcessSnapshot(
            pid: 536,
            parentPID: 530,
            cpuPercent: 0.4,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/node_repl"
        )
        let mcp = ProcessSnapshot(
            pid: 537,
            parentPID: 530,
            cpuPercent: 0.8,
            state: "S",
            command: "npm exec xcodebuildmcp@latest mcp"
        )
        let appServer = ProcessSnapshot(
            pid: 538,
            parentPID: 530,
            cpuPercent: 0.0,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        )

        let report = AgentDetector.report(
            from: [codexApp, renderer, gpuHelper, utility, crashpad, chronicle, nodeRepl, mcp, appServer],
            selfPID: 999
        )

        XCTAssertFalse(report.isActive)
    }

    func testDetectsBusyCodexGuiFurnitureWithoutWorkerProcess() {
        let codexApp = ProcessSnapshot(
            pid: 515,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )
        let appServer = ProcessSnapshot(
            pid: 516,
            parentPID: 515,
            cpuPercent: 1.4,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        )

        let report = AgentDetector.report(from: [codexApp, appServer], selfPID: 999)

        XCTAssertTrue(report.isActive)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.sessions[0].kind, .codex)
    }

    func testDetectsLowButMeasurableCodexGuiActivity() {
        let codexApp = ProcessSnapshot(
            pid: 519,
            parentPID: 1,
            cpuPercent: 0.05,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )
        let appServer = ProcessSnapshot(
            pid: 528,
            parentPID: 519,
            cpuPercent: 0.22,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        )

        let report = AgentDetector.report(from: [codexApp, appServer], selfPID: 999)

        XCTAssertTrue(report.isActive)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.sessions[0].kind, .codex)
    }

    func testIgnoresBarelyBusyCodexGuiFurniture() {
        let codexApp = ProcessSnapshot(
            pid: 517,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Codex.app/Contents/MacOS/Codex"
        )
        let appServer = ProcessSnapshot(
            pid: 518,
            parentPID: 517,
            cpuPercent: 0.1,
            state: "S",
            command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"
        )

        let report = AgentDetector.report(from: [codexApp, appServer], selfPID: 999)

        XCTAssertFalse(report.isActive)
    }

    func testDetectsClaudeGuiWorkerDescendant() {
        let claudeApp = ProcessSnapshot(
            pid: 520,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Claude.app/Contents/MacOS/Claude"
        )
        let renderer = ProcessSnapshot(
            pid: 521,
            parentPID: 520,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer"
        )
        let worker = ProcessSnapshot(
            pid: 522,
            parentPID: 521,
            cpuPercent: 5,
            state: "R",
            command: "/usr/bin/swift test"
        )

        let report = AgentDetector.report(from: [claudeApp, renderer, worker], selfPID: 999)

        XCTAssertTrue(report.isActive)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.sessions[0].kind, .claude)
        XCTAssertEqual(report.sessions[0].descendants.map(\.pid), [522])
    }

    func testIgnoresIdleClaudeDesktopLocalAgentProcess() {
        let claudeApp = ProcessSnapshot(
            pid: 523,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Claude.app/Contents/MacOS/Claude"
        )
        let disclaimer = ProcessSnapshot(
            pid: 524,
            parentPID: 523,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Claude.app/Contents/Helpers/disclaimer /Users/me/.claude/local/claude-code/2.1.138/claude.app/Contents/MacOS/claude --permission-mode plan --replay-user-messages"
        )
        let localAgent = ProcessSnapshot(
            pid: 525,
            parentPID: 524,
            cpuPercent: 0,
            state: "S",
            command: "/Users/me/.claude/local/claude-code/2.1.138/claude.app/Contents/MacOS/claude --output-format stream-json --permission-mode plan --replay-user-messages"
        )

        let report = AgentDetector.report(from: [claudeApp, disclaimer, localAgent], selfPID: 999)

        XCTAssertFalse(report.isActive)
    }

    func testDetectsBusyClaudeDesktopLocalAgentProcess() {
        let claudeApp = ProcessSnapshot(
            pid: 526,
            parentPID: 1,
            cpuPercent: 0,
            state: "S",
            command: "/Applications/Claude.app/Contents/MacOS/Claude"
        )
        let localAgent = ProcessSnapshot(
            pid: 527,
            parentPID: 526,
            cpuPercent: 1.8,
            state: "R",
            command: "/Users/me/.claude/local/claude-code/2.1.138/claude.app/Contents/MacOS/claude --output-format stream-json --permission-mode plan"
        )

        let report = AgentDetector.report(from: [claudeApp, localAgent], selfPID: 999)

        XCTAssertTrue(report.isActive)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.sessions[0].kind, .claude)
        XCTAssertEqual(report.sessions[0].descendants.map(\.pid), [527])
    }

    func testIncludesChildProcessesInSession() {
        let codex = ProcessSnapshot(
            pid: 400,
            parentPID: 1,
            cpuPercent: 0.2,
            state: "S",
            command: "/opt/homebrew/bin/codex"
        )
        let shell = ProcessSnapshot(
            pid: 401,
            parentPID: 400,
            cpuPercent: 0.5,
            state: "S",
            command: "/bin/zsh -lc swift test"
        )
        let swift = ProcessSnapshot(
            pid: 402,
            parentPID: 401,
            cpuPercent: 8.2,
            state: "R",
            command: "/usr/bin/swift test"
        )

        let report = AgentDetector.report(from: [codex, shell, swift], selfPID: 999)

        XCTAssertTrue(report.isActive)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertEqual(report.sessions[0].kind, .codex)
        XCTAssertEqual(report.sessions[0].processCount, 3)
        XCTAssertEqual(report.totalProcessCount, 3)
    }
}
