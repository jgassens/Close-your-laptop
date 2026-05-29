import Foundation
import Darwin
import OSLog

final class ClamshellSleepController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gassensmith.closeyourlaptop",
        category: "Power"
    )
    private let authorizationRetryCooldownSeconds: TimeInterval = 300
    private let heartbeatTimeoutSeconds = 180
    private let watchdogIntervalSeconds = 15
    private let heartbeatURL: URL
    private let authorizationQueue = DispatchQueue(label: "com.gassensmith.closeyourlaptop.clamshell")
    private let processLock = NSLock()

    private var state = State.inactive
    private var authorizationProcess: Process?
    private var nextAuthorizationAttemptDate: Date?
    private(set) var lastErrorDescription: String?

    var isActive: Bool {
        if case .ready(_, true) = state {
            return true
        }

        return false
    }

    var statusLine: String? {
        switch state {
        case .ready(_, true):
            return "Closed-lid battery mode is armed."
        case .pending:
            return "Closed-lid battery mode is awaiting administrator approval."
        case .ready(_, false), .inactive:
            return nil
        }
    }

    init(
        heartbeatURL: URL = URL(fileURLWithPath: "/private/tmp/com.gassensmith.closeyourlaptop.clamshell")
    ) {
        self.heartbeatURL = heartbeatURL
    }

    func setEnabled(_ enabled: Bool, reason: String) {
        switch state {
        case .ready(let helper, let currentlyEnabled):
            guard helperIsHealthy(helper) else {
                markHelperLost(helper, enabled: enabled, reason: reason)
                return
            }

            updateHelper(helper: helper, enabled: enabled)
            if currentlyEnabled != enabled {
                let mode = enabled ? "armed" : "disarmed"
                logger.notice("closed-lid battery mode \(mode, privacy: .public); reason=\(reason, privacy: .public)")
            }
        case .pending(let token, let currentlyEnabled):
            updatePendingHelper(token: token, enabled: enabled)
            if currentlyEnabled != enabled {
                let mode = enabled ? "pending armed" : "pending disarmed"
                logger.notice("closed-lid battery mode \(mode, privacy: .public); reason=\(reason, privacy: .public)")
            }
        case .inactive:
            guard enabled else {
                return
            }

            startHelper(reason: reason)
        }
    }

    func shutdown() {
        guard state != .inactive else {
            return
        }

        state = .inactive
        cancelAuthorizationProcess()
        try? FileManager.default.removeItem(at: heartbeatURL)
        logger.notice("closed-lid battery mode shutdown requested")
    }

    private func startHelper(reason: String) {
        if let nextAuthorizationAttemptDate, Date() < nextAuthorizationAttemptDate {
            return
        }

        let nextToken = UUID().uuidString

        do {
            try writeHeartbeat(token: nextToken, enabled: true)
            state = .pending(nextToken, true)
            lastErrorDescription = nil
            logger.notice("closed-lid battery mode authorization requested; reason=\(reason, privacy: .public)")
            requestAuthorization(token: nextToken, reason: reason)
        } catch {
            state = .inactive
            try? FileManager.default.removeItem(at: heartbeatURL)
            lastErrorDescription = "Closed-lid battery mode failed: \(error.localizedDescription)"
            logger.error("closed-lid battery mode failed; error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateHelper(helper: HelperState, enabled: Bool) {
        do {
            try writeHeartbeat(token: helper.token, enabled: enabled)
            switch state {
            case .ready(let currentHelper, _) where currentHelper == helper:
                state = .ready(helper, enabled)
            case .pending(let currentToken, _) where currentToken == helper.token:
                state = .pending(helper.token, enabled)
            case .inactive, .pending, .ready:
                break
            }
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = "Closed-lid heartbeat failed: \(error.localizedDescription)"
            logger.error("closed-lid heartbeat failed; error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func updatePendingHelper(token: String, enabled: Bool) {
        do {
            try writeHeartbeat(token: token, enabled: enabled)
            switch state {
            case .pending(let currentToken, _) where currentToken == token:
                state = .pending(token, enabled)
            case .inactive, .pending, .ready:
                break
            }
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = "Closed-lid heartbeat failed: \(error.localizedDescription)"
            logger.error("closed-lid heartbeat failed; error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestAuthorization(token: String, reason: String) {
        authorizationQueue.async { [weak self] in
            guard let self else {
                return
            }

            let result = Result {
                try self.runPrivilegedHelperScript(token: token)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                switch result {
                case .success(let helperPID):
                    guard case .pending(let currentToken, let desiredEnabled) = self.state,
                          currentToken == token else {
                        self.logger.notice("closed-lid battery mode authorization finished after release")
                        return
                    }

                    let helper = HelperState(token: token, pid: helperPID)
                    self.state = .ready(helper, desiredEnabled)
                    self.nextAuthorizationAttemptDate = nil
                    self.lastErrorDescription = nil
                    let mode = desiredEnabled ? "armed" : "ready"
                    self.logger.notice(
                        "closed-lid battery mode \(mode, privacy: .public); helperPID=\(helperPID, privacy: .public) reason=\(reason, privacy: .public)"
                    )
                case .failure(let error):
                    guard case .pending(let currentToken, _) = self.state,
                          currentToken == token else {
                        return
                    }

                    self.state = .inactive
                    self.nextAuthorizationAttemptDate = Date()
                        .addingTimeInterval(self.authorizationRetryCooldownSeconds)
                    try? FileManager.default.removeItem(at: self.heartbeatURL)
                    self.lastErrorDescription = "Closed-lid battery mode failed: \(error.localizedDescription)"
                    self.logger.error(
                        "closed-lid battery mode failed; error=\(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private func helperIsHealthy(_ helper: HelperState) -> Bool {
        guard isProcessAlive(pid: helper.pid),
              let heartbeat = currentHeartbeat(),
              heartbeat.token == helper.token,
              heartbeat.age <= TimeInterval(heartbeatTimeoutSeconds) else {
            return false
        }

        return true
    }

    private func markHelperLost(_ helper: HelperState, enabled: Bool, reason: String) {
        state = .inactive
        try? FileManager.default.removeItem(at: heartbeatURL)
        lastErrorDescription = nil
        logger.notice(
            "closed-lid battery helper missing; helperPID=\(helper.pid, privacy: .public) restarting=\(enabled ? "yes" : "no", privacy: .public) reason=\(reason, privacy: .public)"
        )

        if enabled {
            startHelper(reason: reason)
        }
    }

    private func currentHeartbeat() -> Heartbeat? {
        guard let contents = try? String(contentsOf: heartbeatURL, encoding: .utf8),
              let token = contents.split(separator: "\n", omittingEmptySubsequences: false).first,
              let attributes = try? FileManager.default.attributesOfItem(atPath: heartbeatURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return Heartbeat(token: String(token), age: Date().timeIntervalSince(modificationDate))
    }

    private func isProcessAlive(pid: pid_t) -> Bool {
        guard pid > 0 else {
            return false
        }

        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private func writeHeartbeat(token: String, enabled: Bool) throws {
        let mode = enabled ? "enabled" : "disabled"
        let contents = "\(token)\n\(mode)\n"
        try contents.write(to: heartbeatURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [
                .modificationDate: Date(),
                .posixPermissions: 0o600
            ],
            ofItemAtPath: heartbeatURL.path
        )
    }

    private func runPrivilegedHelperScript(token: String) throws -> pid_t {
        let script = shellScript(token: token)
        let prompt = "Close Your Laptop needs administrator approval to manage closed-lid sleep while Claude or Codex is actively working."
        let appleScript = "do shell script \(appleScriptLiteral(script)) with administrator privileges with prompt \(appleScriptLiteral(prompt))"
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = output
        process.standardError = output

        setAuthorizationProcess(process)
        defer {
            clearAuthorizationProcess(process)
        }

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ClamshellSleepError.privilegedCommandFailed(message ?? "osascript exited \(process.terminationStatus)")
        }

        guard let message,
              let helperPID = pid_t(message),
              helperPID > 0 else {
            throw ClamshellSleepError.invalidHelperPID(message ?? "missing helper pid")
        }

        return helperPID
    }

    private func setAuthorizationProcess(_ process: Process) {
        processLock.lock()
        authorizationProcess = process
        processLock.unlock()
    }

    private func clearAuthorizationProcess(_ process: Process) {
        processLock.lock()
        if authorizationProcess === process {
            authorizationProcess = nil
        }
        processLock.unlock()
    }

    private func cancelAuthorizationProcess() {
        processLock.lock()
        let process = authorizationProcess
        authorizationProcess = nil
        processLock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func shellScript(token: String) -> String {
        let path = shellSingleQuoted(heartbeatURL.path)
        let shellToken = shellSingleQuoted(token)

        return """
        (
          token=\(shellToken)
          file=\(path)
          timeout=\(heartbeatTimeoutSeconds)
          interval=\(watchdogIntervalSeconds)
          armed=unknown

          while true; do
            if [ ! -e "$file" ]; then
              /usr/bin/pmset -a disablesleep 0
              exit 0
            fi

            current=$(/usr/bin/sed -n '1p' "$file" 2>/dev/null || true)
            desired=$(/usr/bin/sed -n '2p' "$file" 2>/dev/null || true)
            if [ "$current" != "$token" ]; then
              exit 0
            fi

            now=$(/bin/date +%s)
            modified=$(/usr/bin/stat -f %m "$file" 2>/dev/null || echo 0)
            age=$((now - modified))
            if [ "$age" -gt "$timeout" ]; then
              /usr/bin/pmset -a disablesleep 0
              /bin/rm -f "$file"
              exit 0
            fi

            if [ "$desired" = "enabled" ]; then
              if [ "$armed" != "1" ]; then
                /usr/bin/pmset -a disablesleep 1
                armed=1
              fi
            else
              if [ "$armed" != "0" ]; then
                /usr/bin/pmset -a disablesleep 0
                armed=0
              fi
            fi

            /bin/sleep "$interval"
          done
        ) >/dev/null 2>&1 &
        echo $!
        """
    }

    private func shellSingleQuoted(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptLiteral(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private struct HelperState: Equatable {
    let token: String
    let pid: pid_t
}

private struct Heartbeat {
    let token: String
    let age: TimeInterval
}

private enum State: Equatable {
    case inactive
    case pending(String, Bool)
    case ready(HelperState, Bool)
}

private enum ClamshellSleepError: LocalizedError {
    case privilegedCommandFailed(String)
    case invalidHelperPID(String)

    var errorDescription: String? {
        switch self {
        case .privilegedCommandFailed(let message):
            return message.isEmpty ? "administrator approval was not granted" : message
        case .invalidHelperPID(let message):
            return "closed-lid helper did not report a valid process id: \(message)"
        }
    }
}
