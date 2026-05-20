import AppKit
import Foundation
import OSLog

private final class Watcher {
    private let logger = Logger(
        subsystem: "com.gassensmith.closeyourlaptop.watcher",
        category: "Lifecycle"
    )
    private let watchedBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.anthropic.claudefordesktop"
    ]
    private let sidecarBundleID = "com.gassensmith.closeyourlaptop"
    private let sidecarPath: String

    init() {
        sidecarPath = ProcessInfo.processInfo.environment["CYL_APP_PATH"]
            ?? "/Applications/Close Your Laptop.app"
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(applicationDidLaunch),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        if anyWatchedAppRunning() {
            logger.notice("watched app already running; starting sidecar")
            startSidecar()
        } else {
            logger.notice("watcher ready; no watched app running")
        }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard let app = watchedApplication(from: notification) else {
            return
        }

        logger.notice("watched app launched; bundleID=\(app.bundleIdentifier ?? "unknown", privacy: .public)")
        startSidecar()
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let app = watchedApplication(from: notification) else {
            return
        }

        logger.notice("watched app terminated; bundleID=\(app.bundleIdentifier ?? "unknown", privacy: .public)")
        if !anyWatchedAppRunning() {
            logger.notice("no watched apps remain; sidecar will self-quit when idle")
        }
    }

    private func startSidecar() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: sidecarBundleID).isEmpty else {
            logger.notice("sidecar already running")
            return
        }

        let appURL = URL(fileURLWithPath: sidecarPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            logger.error("sidecar app missing; path=\(self.sidecarPath, privacy: .public)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [logger] _, error in
            if let error {
                logger.error("sidecar launch failed; error=\(error.localizedDescription, privacy: .public)")
            } else {
                logger.notice("sidecar launch requested")
            }
        }
    }

    private func anyWatchedAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleIdentifier = app.bundleIdentifier else {
                return false
            }

            return watchedBundleIDs.contains(bundleIdentifier)
        }
    }

    private func watchedApplication(from notification: Notification) -> NSRunningApplication? {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleIdentifier = app.bundleIdentifier,
              watchedBundleIDs.contains(bundleIdentifier) else {
            return nil
        }

        return app
    }
}

private let watcher = Watcher()
watcher.start()
RunLoop.main.run()
