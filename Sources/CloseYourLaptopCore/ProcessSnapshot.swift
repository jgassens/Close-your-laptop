import Foundation

public struct ProcessSnapshot: Equatable, Hashable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let cpuPercent: Double
    public let cpuTimeNanoseconds: UInt64
    public let state: String
    public let command: String

    public init(
        pid: Int32,
        parentPID: Int32,
        cpuPercent: Double,
        cpuTimeNanoseconds: UInt64 = 0,
        state: String,
        command: String
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.cpuPercent = cpuPercent
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.state = state
        self.command = command
    }

    public var executableName: String {
        guard let firstToken = command.split(separator: " ", maxSplits: 1).first else {
            return ""
        }

        let trimmed = String(firstToken).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return URL(fileURLWithPath: trimmed).lastPathComponent.lowercased()
    }

}
