import Foundation
import Darwin

public final class ProcessScanner {
    private var previousCPUTimeByPID: [Int32: UInt64] = [:]
    private var previousScanDate: Date?

    private let argumentBearingExecutables: Set<String> = [
        "claude",
        "claude-code",
        "codex",
        "codex-cli",
        "node",
        "npm",
        "npx",
        "pnpm",
        "yarn",
        "bun",
        "deno"
    ]

    public init() {}

    public func resetCPUHistory() {
        previousCPUTimeByPID = [:]
        previousScanDate = nil
    }

    public func scan() -> [ProcessSnapshot] {
        let now = Date()
        let snapshots = nativeScan()
        let elapsed = previousScanDate.map { now.timeIntervalSince($0) } ?? 0
        let measuredSnapshots = snapshots.map { snapshot in
            measuredSnapshot(snapshot, elapsed: elapsed)
        }

        previousCPUTimeByPID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0.cpuTimeNanoseconds) })
        previousScanDate = now

        return measuredSnapshots
    }

    private func nativeScan() -> [ProcessSnapshot] {
        listPIDs().compactMap(snapshot(for:))
    }

    private func listPIDs() -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else {
            return []
        }

        let capacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)

        let actualByteCount = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }

        guard actualByteCount > 0 else {
            return []
        }

        let count = min(Int(actualByteCount) / MemoryLayout<pid_t>.stride, pids.count)
        return pids.prefix(count).filter { $0 > 0 }
    }

    private func snapshot(for pid: pid_t) -> ProcessSnapshot? {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize)

        guard result == infoSize else {
            return nil
        }

        let processName = commandName(from: info)
        let path = executablePath(for: pid) ?? processName
        let executableName = executableName(from: path)
        let arguments = shouldReadArguments(
            path: path,
            processName: processName,
            executableName: executableName
        ) ? arguments(for: pid) : []
        let command = arguments.isEmpty ? path : arguments.joined(separator: " ")

        return ProcessSnapshot(
            pid: pid,
            parentPID: Int32(info.pbi_ppid),
            cpuPercent: 0,
            cpuTimeNanoseconds: cpuTimeNanoseconds(for: pid),
            state: statusString(info.pbi_status),
            command: command
        )
    }

    private func measuredSnapshot(_ snapshot: ProcessSnapshot, elapsed: TimeInterval) -> ProcessSnapshot {
        guard elapsed > 0,
              let previousCPUTime = previousCPUTimeByPID[snapshot.pid],
              snapshot.cpuTimeNanoseconds >= previousCPUTime else {
            return snapshot
        }

        let cpuDeltaSeconds = Double(snapshot.cpuTimeNanoseconds - previousCPUTime) / 1_000_000_000
        let cpuPercent = (cpuDeltaSeconds / elapsed) * 100

        return ProcessSnapshot(
            pid: snapshot.pid,
            parentPID: snapshot.parentPID,
            cpuPercent: cpuPercent,
            cpuTimeNanoseconds: snapshot.cpuTimeNanoseconds,
            state: snapshot.state,
            command: snapshot.command
        )
    }

    private func cpuTimeNanoseconds(for pid: pid_t) -> UInt64 {
        var info = proc_taskinfo()
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize)

        guard result == infoSize else {
            return 0
        }

        return info.pti_total_user + info.pti_total_system
    }

    private func shouldReadArguments(path: String, processName: String, executableName: String) -> Bool {
        if argumentBearingExecutables.contains(executableName) {
            return true
        }

        let loweredPath = path.lowercased()
        let loweredProcessName = processName.lowercased()

        return loweredPath.contains("claude") ||
            loweredPath.contains("codex") ||
            loweredProcessName.contains("claude") ||
            loweredProcessName.contains("codex")
    }

    private func executableName(from path: String) -> String {
        var trimmed = path
        while trimmed.first == "\"" || trimmed.first == "'" {
            trimmed.removeFirst()
        }
        while trimmed.last == "\"" || trimmed.last == "'" {
            trimmed.removeLast()
        }

        return trimmed.split(separator: "/").last.map { String($0).lowercased() } ?? trimmed.lowercased()
    }

    private func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))

        guard length > 0 else {
            return nil
        }

        return String(cString: buffer)
    }

    private func commandName(from info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { bytes in
            let characters = bytes.prefix { $0 != 0 }
            return String(decoding: characters, as: UTF8.self)
        }
    }

    private func arguments(for pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0

        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            sysctl(&mib, u_int(mib.count), pointer.baseAddress, &size, nil, 0)
        }

        guard result == 0 else {
            return []
        }

        return parseProcessArguments(buffer)
    }

    private func parseProcessArguments(_ buffer: [CChar]) -> [String] {
        guard buffer.count > MemoryLayout<Int32>.size else {
            return []
        }

        var argc: Int32 = 0
        _ = buffer.withUnsafeBufferPointer { pointer in
            memcpy(&argc, pointer.baseAddress!, MemoryLayout<Int32>.size)
        }

        var index = MemoryLayout<Int32>.size

        while index < buffer.count && buffer[index] != 0 {
            index += 1
        }

        while index < buffer.count && buffer[index] == 0 {
            index += 1
        }

        var arguments: [String] = []

        for _ in 0..<max(0, Int(argc)) {
            guard index < buffer.count else {
                break
            }

            let start = index
            while index < buffer.count && buffer[index] != 0 {
                index += 1
            }

            if index > start {
                var stringBuffer = Array(buffer[start..<index])
                stringBuffer.append(0)
                let argument = stringBuffer.withUnsafeBufferPointer { pointer in
                    String(cString: pointer.baseAddress!)
                }
                arguments.append(argument)
            }

            while index < buffer.count && buffer[index] == 0 {
                index += 1
            }
        }

        return arguments
    }

    private func statusString(_ status: UInt32) -> String {
        switch status {
        case UInt32(SIDL):
            return "I"
        case UInt32(SRUN):
            return "R"
        case UInt32(SSLEEP):
            return "S"
        case UInt32(SSTOP):
            return "T"
        case UInt32(SZOMB):
            return "Z"
        default:
            return "\(status)"
        }
    }
}
