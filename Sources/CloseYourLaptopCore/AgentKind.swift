public enum AgentKind: String, CaseIterable, Hashable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }
}
