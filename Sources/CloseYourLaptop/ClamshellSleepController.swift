import Foundation
import OSLog

final class ClamshellSleepController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gassensmith.closeyourlaptop",
        category: "Power"
    )
    private let heartbeatURL: URL
    private let helperController = ClamshellHelperController()

    private var desiredEnabled = false
    private var lastLoggedMode: Bool?
    private var lastLoggedHelperState: ClamshellHelperInstallationState?
    private(set) var lastErrorDescription: String?

    var isActive: Bool {
        desiredEnabled && helperController.isInstalled
    }

    var statusLine: String? {
        guard desiredEnabled else {
            return nil
        }

        switch helperController.installationState() {
        case .current:
            return "Closed-lid battery mode is armed."
        case .stale:
            return "Closed-lid helper should be updated in Preferences."
        case .notInstalled:
            return "Closed-lid helper is not installed."
        }
    }

    init(
        heartbeatURL: URL = URL(fileURLWithPath: "/private/tmp/com.gassensmith.closeyourlaptop.clamshell")
    ) {
        self.heartbeatURL = heartbeatURL
    }

    func setEnabled(_ enabled: Bool, reason: String) {
        desiredEnabled = enabled

        do {
            try writeHeartbeat(enabled: enabled)
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = "Closed-lid heartbeat failed: \(error.localizedDescription)"
            logger.error("closed-lid heartbeat failed; error=\(error.localizedDescription, privacy: .public)")
            return
        }

        if enabled {
            logHelperAvailabilityIfNeeded(reason: reason)
        }

        if lastLoggedMode != enabled {
            lastLoggedMode = enabled
            let mode = enabled ? "requested" : "released"
            logger.notice("closed-lid battery mode \(mode, privacy: .public); reason=\(reason, privacy: .public)")
        }
    }

    func shutdown() {
        desiredEnabled = false
        lastLoggedMode = nil
        try? writeHeartbeat(enabled: false)
        try? FileManager.default.removeItem(at: heartbeatURL)
        logger.notice("closed-lid battery mode shutdown requested")
    }

    private func logHelperAvailabilityIfNeeded(reason: String) {
        let installationState = helperController.installationState()
        guard installationState != lastLoggedHelperState else {
            return
        }

        lastLoggedHelperState = installationState

        switch installationState {
        case .current:
            logger.notice("closed-lid helper is installed; reason=\(reason, privacy: .public)")
        case .stale:
            logger.notice("closed-lid helper is stale; reason=\(reason, privacy: .public)")
        case .notInstalled:
            logger.notice("closed-lid helper is not installed; reason=\(reason, privacy: .public)")
        }
    }

    private func writeHeartbeat(enabled: Bool) throws {
        let mode = enabled ? "enabled" : "disabled"
        let contents = "\(mode)\n\(Int(Date().timeIntervalSince1970))\n"
        try contents.write(to: heartbeatURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [
                .modificationDate: Date(),
                .posixPermissions: 0o600
            ],
            ofItemAtPath: heartbeatURL.path
        )
    }
}
