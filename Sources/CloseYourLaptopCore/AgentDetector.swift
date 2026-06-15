import Foundation

public enum AgentDetector {
    private static let minimumGUIActivityCPUPercent = 0.1
    private static let minimumReportedGUIProcessCPUPercent = 0.1

    public static func report(
        from processes: [ProcessSnapshot],
        selfPID: Int32 = Int32(ProcessInfo.processInfo.processIdentifier)
    ) -> AgentActivityReport {
        let processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let processesByParent = Dictionary(grouping: processes, by: \.parentPID)
        let guiRoots = processes
            .filter { $0.pid != selfPID }
            .compactMap { process -> (ProcessSnapshot, AgentKind)? in
                guard let kind = guiKind(for: process) else {
                    return nil
                }
                return (process, kind)
            }
            .sorted { $0.0.pid < $1.0.pid }
        let guiRootPIDs = Set(guiRoots.map { $0.0.pid })
        let guiSessions = guiRoots.compactMap { root, kind -> AgentSession? in
            var visited = Set<Int32>()
            let guiDescendants = descendants(of: root.pid, processesByParent: processesByParent, visited: &visited)
            let workDescendants = guiDescendants.filter { !isGUIInfrastructure($0) }
            let guiCPUPercent = workDescendants.reduce(0) { $0 + $1.cpuPercent }

            guard guiCPUPercent > minimumGUIActivityCPUPercent else {
                return nil
            }

            let activeDescendants = workDescendants
                .filter { $0.pid != selfPID }
                .filter { $0.cpuPercent >= minimumReportedGUIProcessCPUPercent }
                .sorted { $0.pid < $1.pid }

            return AgentSession(kind: kind, root: root, descendants: activeDescendants)
        }

        let matches = processes
            .filter { $0.pid != selfPID }
            .filter { !hasAncestor(of: $0, in: guiRootPIDs, processesByPID: processesByPID) }
            .compactMap { process -> (ProcessSnapshot, AgentKind)? in
                guard let kind = kind(for: process) else {
                    return nil
                }
                return (process, kind)
            }

        let matchedPIDs = Set(matches.map { $0.0.pid })
        let roots = matches
            .filter { process, _ in
                !hasAncestor(of: process, in: matchedPIDs, processesByPID: processesByPID)
            }
            .sorted { $0.0.pid < $1.0.pid }

        let sessions = roots.map { root, kind in
            var visited = Set<Int32>()
            let descendants = descendants(of: root.pid, processesByParent: processesByParent, visited: &visited)
                .sorted { $0.pid < $1.pid }

            return AgentSession(kind: kind, root: root, descendants: descendants)
        }

        return AgentActivityReport(sessions: guiSessions + sessions)
    }

    public static func kind(for process: ProcessSnapshot) -> AgentKind? {
        let command = process.command.lowercased()
        let executable = process.executableName

        if command.contains("codex_chronicle") ||
            command.contains(" codex app-server") ||
            command.contains("/codex app-server") ||
            command.contains("sparkle.framework") ||
            command.contains("/updater.app/") {
            return nil
        }

        if command.contains(".app/contents/") &&
            !command.contains(" codex exec") &&
            !command.contains("/codex exec") &&
            !command.contains(" claude-code") &&
            !command.contains("/claude-code") {
            return nil
        }

        if executable == "claude" || executable == "claude-code" {
            return .claude
        }

        if command.contains("@anthropic-ai/claude-code") || command.contains("claude-code") {
            return .claude
        }

        if executable == "codex" || executable == "codex-cli" {
            return .codex
        }

        if command.contains("@openai/codex") ||
            command.contains("openai/codex") ||
            command.contains("codex-cli") {
            return .codex
        }

        return nil
    }

    public static func guiKind(for process: ProcessSnapshot) -> AgentKind? {
        let command = process.command.lowercased()

        if command.contains("/applications/codex.app/contents/macos/codex") {
            return .codex
        }

        if command.contains("/applications/claude.app/contents/macos/claude") {
            return .claude
        }

        return nil
    }

    private static func isGUIInfrastructure(_ process: ProcessSnapshot) -> Bool {
        let command = process.command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = process.executableName

        if command.contains("--type=renderer") ||
            command.contains("--type=gpu-process") ||
            command.contains("--type=utility") {
            return true
        }

        if command.contains("crashpad_handler") ||
            command.contains("codex_chronicle") {
            return true
        }

        if executable == "node_repl" {
            return true
        }

        if command.hasSuffix(" mcp") {
            return true
        }

        return false
    }

    private static func hasAncestor(
        of process: ProcessSnapshot,
        in candidatePIDs: Set<Int32>,
        processesByPID: [Int32: ProcessSnapshot]
    ) -> Bool {
        var currentParent = process.parentPID
        var visited = Set<Int32>()

        while currentParent > 0 && !visited.contains(currentParent) {
            if candidatePIDs.contains(currentParent) {
                return true
            }

            visited.insert(currentParent)
            currentParent = processesByPID[currentParent]?.parentPID ?? 0
        }

        return false
    }

    private static func descendants(
        of pid: Int32,
        processesByParent: [Int32: [ProcessSnapshot]],
        visited: inout Set<Int32>
    ) -> [ProcessSnapshot] {
        guard !visited.contains(pid) else {
            return []
        }

        visited.insert(pid)
        let children = processesByParent[pid] ?? []
        return children + children.flatMap { child in
            descendants(of: child.pid, processesByParent: processesByParent, visited: &visited)
        }
    }
}
