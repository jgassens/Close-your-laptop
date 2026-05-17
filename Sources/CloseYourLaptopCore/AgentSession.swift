public struct AgentSession: Equatable, Sendable {
    public let kind: AgentKind
    public let root: ProcessSnapshot
    public let descendants: [ProcessSnapshot]

    public init(kind: AgentKind, root: ProcessSnapshot, descendants: [ProcessSnapshot]) {
        self.kind = kind
        self.root = root
        self.descendants = descendants
    }

    public var processes: [ProcessSnapshot] {
        [root] + descendants
    }

    public var processCount: Int {
        processes.count
    }

    public var totalCPUPercent: Double {
        processes.reduce(0) { $0 + $1.cpuPercent }
    }
}

public struct AgentActivityReport: Equatable, Sendable {
    public let sessions: [AgentSession]

    public init(sessions: [AgentSession]) {
        self.sessions = sessions
    }

    public var isActive: Bool {
        !sessions.isEmpty
    }

    public var detectedKinds: [AgentKind] {
        Array(Set(sessions.map(\.kind))).sorted { $0.displayName < $1.displayName }
    }

    public var totalCPUPercent: Double {
        sessions.reduce(0) { $0 + $1.totalCPUPercent }
    }

    public var totalProcessCount: Int {
        sessions.reduce(0) { $0 + $1.processCount }
    }

    public var summary: String {
        guard isActive else {
            return "No Claude or Codex work is active."
        }

        let names = detectedKinds.map(\.displayName).joined(separator: " + ")
        return "\(names): \(totalProcessCount) process\(totalProcessCount == 1 ? "" : "es")"
    }
}
