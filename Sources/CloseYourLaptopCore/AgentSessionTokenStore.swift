import Darwin
import Foundation

public struct AgentSessionToken: Equatable, Sendable {
    public let id: String
    public let kind: AgentKind
    public let pid: Int32
    public let updatedAt: Date

    public init(id: String, kind: AgentKind, pid: Int32, updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.pid = pid
        self.updatedAt = updatedAt
    }
}

public final class AgentSessionTokenStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL = AgentSessionTokenStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public static func defaultDirectoryURL() -> URL {
        let temporaryRoot = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return temporaryRoot.appendingPathComponent(
            "com.gassensmith.closeyourlaptop.sessions",
            isDirectory: true
        )
    }

    public func begin(kind: AgentKind, token: String, pid: Int32) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let now = Date()
        let body = [
            "kind=\(kind.rawValue)",
            "pid=\(pid)",
            "updated=\(now.timeIntervalSince1970)"
        ].joined(separator: "\n")

        try body.write(to: url(for: token), atomically: true, encoding: .utf8)
    }

    public func end(token: String) throws {
        let url = url(for: token)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    public func activeSessions() -> [AgentSessionToken] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap(activeSession).sorted { $0.id < $1.id }
    }

    private func activeSession(from url: URL) -> AgentSessionToken? {
        guard let token = parse(url: url) else {
            return nil
        }

        guard token.pid <= 0 || isProcessAlive(pid: token.pid) else {
            try? fileManager.removeItem(at: url)
            return nil
        }

        return token
    }

    private func parse(url: URL) -> AgentSessionToken? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let pairs = Dictionary(
            uniqueKeysWithValues: text
                .split(separator: "\n")
                .compactMap { line -> (String, String)? in
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else {
                        return nil
                    }

                    return (String(parts[0]), String(parts[1]))
                }
        )

        guard let kindRaw = pairs["kind"],
              let kind = AgentKind(rawValue: kindRaw),
              let pidString = pairs["pid"],
              let pid = Int32(pidString) else {
            return nil
        }

        let updatedInterval = pairs["updated"].flatMap(TimeInterval.init) ?? 0
        return AgentSessionToken(
            id: url.deletingPathExtension().lastPathComponent,
            kind: kind,
            pid: pid,
            updatedAt: Date(timeIntervalSince1970: updatedInterval)
        )
    }

    private func url(for token: String) -> URL {
        directoryURL
            .appendingPathComponent(safeToken(token), isDirectory: false)
            .appendingPathExtension("session")
    }

    private func safeToken(_ token: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = token.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let cleaned = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }
}
