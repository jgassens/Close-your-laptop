import Foundation
import OSLog

private final class ClamshellHelper {
    private let logger = Logger(
        subsystem: "com.gassensmith.closeyourlaptop.clamshell-helper",
        category: "Power"
    )
    private let heartbeatURL = URL(fileURLWithPath: "/private/tmp/com.gassensmith.closeyourlaptop.clamshell")
    private let heartbeatTimeoutSeconds: TimeInterval = 180
    private let intervalSeconds: TimeInterval = 5

    private var isArmed = false

    func run() {
        logger.notice("closed-lid helper started")
        while true {
            autoreleasepool {
                reconcile()
            }
            Thread.sleep(forTimeInterval: intervalSeconds)
        }
    }

    private func reconcile() {
        guard let heartbeat = currentHeartbeat() else {
            disarmIfNeeded(reason: "heartbeat missing")
            return
        }

        guard heartbeat.age <= heartbeatTimeoutSeconds else {
            disarmIfNeeded(reason: "heartbeat stale")
            try? FileManager.default.removeItem(at: heartbeatURL)
            return
        }

        if heartbeat.enabled {
            armIfNeeded()
        } else {
            disarmIfNeeded(reason: "heartbeat disabled")
        }
    }

    private func currentHeartbeat() -> Heartbeat? {
        guard let contents = try? String(contentsOf: heartbeatURL, encoding: .utf8),
              let attributes = try? FileManager.default.attributesOfItem(atPath: heartbeatURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else {
            return nil
        }

        return Heartbeat(
            enabled: firstLine == "enabled",
            age: Date().timeIntervalSince(modificationDate)
        )
    }

    private func armIfNeeded() {
        guard !isArmed else {
            return
        }

        runPMSet(disableSleep: true)
        isArmed = true
        logger.notice("closed-lid battery mode armed")
    }

    private func disarmIfNeeded(reason: String) {
        guard isArmed else {
            return
        }

        runPMSet(disableSleep: false)
        isArmed = false
        logger.notice("closed-lid battery mode disarmed; reason=\(reason, privacy: .public)")
    }

    private func runPMSet(disableSleep: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disableSleep ? "1" : "0"]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                logger.error("pmset failed; status=\(process.terminationStatus, privacy: .public)")
            }
        } catch {
            logger.error("pmset failed; error=\(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct Heartbeat {
    let enabled: Bool
    let age: TimeInterval
}

if CommandLine.arguments.contains("--version") {
    print("1")
    exit(EXIT_SUCCESS)
}

ClamshellHelper().run()
