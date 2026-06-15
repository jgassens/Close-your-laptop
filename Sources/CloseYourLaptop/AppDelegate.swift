import AppKit
import CloseYourLaptopCore
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scanner = ProcessScanner()
    private let cliSessionStore = AgentSessionTokenStore()
    private let powerController = PowerAssertionController()
    private let updateController = UpdateController()
    private let watcherController = WatcherController()
    private let clamshellHelperController = ClamshellHelperController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var preferencesController = PreferencesWindowController(
        onRefresh: { [weak self] in
            self?.refresh()
        },
        onCheckForUpdates: { [weak self] in
            self?.checkForUpdates()
        },
        onInstallClamshellHelper: { [weak self] in
            self?.installClamshellHelper()
        },
        onUninstallClamshellHelper: { [weak self] in
            self?.uninstallClamshellHelper()
        },
        diagnosticsProvider: { [weak self] in
            self?.diagnosticsSummary() ?? "Close Your Laptop diagnostics are unavailable."
        },
        watcherStateProvider: { [weak self] in
            self?.watcherController.installationState() ?? .notInstalled(canInstall: false)
        },
        clamshellHelperStateProvider: { [weak self] in
            self?.clamshellHelperController.installationState() ?? .notInstalled(canInstall: false)
        }
    )
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gassensmith.closeyourlaptop",
        category: "Power"
    )

    private var timer: Timer?
    private var currentRefreshInterval: TimeInterval = 0
    private var lastRenderedState: RenderedState?
    private var lastLoggedActivityState: String?
    private var lastReport = AgentActivityReport(sessions: [])
    private var lastActiveDate: Date?
    private var lastActiveWasDesktopGUI = false
    private var postWakeRevalidationUntil: Date?
    private var wasHoldingAssertionsAtSleep = false
    private var isHoldingForGracePeriod = false
    private var activeCLISessions: [AgentSessionToken] = []
    private var automaticQuitCandidateSince: Date?
    private let launchDate = Date()

    private let releaseGraceSeconds: TimeInterval = 30
    private let desktopReleaseGraceSeconds: TimeInterval = 120
    private let postWakeRevalidationSeconds: TimeInterval = 120
    private let activeRefreshSeconds: TimeInterval = 5
    private let idleRefreshSeconds: TimeInterval = 15
    private let dormantRefreshSeconds: TimeInterval = 60
    private let automaticQuitDelaySeconds: TimeInterval = 20
    private let watchedBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.anthropic.claudefordesktop"
    ]

    private var automaticQuitEnabled: Bool {
        ProcessInfo.processInfo.environment["CYL_DISABLE_AUTO_QUIT"] != "1"
    }

    private var monitoringEnabled: Bool {
        get { AppPreferences.monitoringEnabled }
        set { AppPreferences.monitoringEnabled = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppPreferences.registerDefaults()
        logger.notice("app launched")

        if terminateDuplicateInstanceIfNeeded() {
            return
        }

        updateController.start()
        configurePreferenceNotifications()
        configureWorkspaceNotifications()
        configureStatusItem()
        primeCPUHistoryThenRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.notice("app terminating; releasing sleep assertions")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        powerController.releaseAll()
    }

    @objc private func toggleMonitoring() {
        monitoringEnabled.toggle()
        let state = monitoringEnabled ? "enabled" : "disabled"
        logger.notice("monitoring \(state, privacy: .public)")
        NotificationCenter.default.post(name: AppPreferences.didChangeNotification, object: self)
    }

    @objc private func refreshFromMenu() {
        logger.info("manual refresh requested")
        refresh()
    }

    @objc private func checkForUpdates() {
        updateController.checkForUpdates { [weak self] problem in
            self?.showAlert(title: "Could Not Check for Updates", message: problem)
        }
    }

    @objc private func openPreferences() {
        logger.info("preferences requested")
        preferencesController.showWindow(nil)
    }

    @objc private func installTinyPersistentWatcher() {
        do {
            try watcherController.install()
            logger.notice("tiny persistent watcher installed")
            showAlert(
                title: "Tiny Persistent Watcher Installed",
                message: "Close Your Laptop will now start automatically when Claude or Codex opens."
            )
            updateStatusItem(force: true)
        } catch {
            logger.error("tiny persistent watcher install failed; error=\(error.localizedDescription, privacy: .public)")
            showAlert(title: "Could Not Install Watcher", message: error.localizedDescription)
        }
    }

    @objc private func updateTinyPersistentWatcher() {
        do {
            try watcherController.install()
            logger.notice("tiny persistent watcher updated")
            showAlert(
                title: "Tiny Persistent Watcher Updated",
                message: "The installed watcher now matches this copy of Close Your Laptop."
            )
            updateStatusItem(force: true)
        } catch {
            logger.error("tiny persistent watcher update failed; error=\(error.localizedDescription, privacy: .public)")
            showAlert(title: "Could Not Update Watcher", message: error.localizedDescription)
        }
    }

    @objc private func uninstallTinyPersistentWatcher() {
        do {
            try watcherController.uninstall()
            logger.notice("tiny persistent watcher uninstalled")
            showAlert(
                title: "Tiny Persistent Watcher Uninstalled",
                message: "Close Your Laptop will no longer start automatically when Claude or Codex opens."
            )
            updateStatusItem(force: true)
        } catch {
            logger.error("tiny persistent watcher uninstall failed; error=\(error.localizedDescription, privacy: .public)")
            showAlert(title: "Could Not Uninstall Watcher", message: error.localizedDescription)
        }
    }

    private func installClamshellHelper() {
        do {
            try clamshellHelperController.install()
            logger.notice("closed-lid helper installed")
            showAlert(
                title: "Closed-Lid Helper Installed",
                message: "Close Your Laptop can now manage closed-lid battery sleep without asking for administrator approval on every app launch."
            )
            refresh()
        } catch {
            logger.error("closed-lid helper install failed; error=\(error.localizedDescription, privacy: .public)")
            showAlert(title: "Could Not Install Closed-Lid Helper", message: error.localizedDescription)
        }
    }

    private func uninstallClamshellHelper() {
        do {
            try clamshellHelperController.uninstall()
            logger.notice("closed-lid helper uninstalled")
            showAlert(
                title: "Closed-Lid Helper Uninstalled",
                message: "Close Your Laptop will still hold ordinary sleep assertions, but closed-lid battery mode will not be managed."
            )
            refresh()
        } catch {
            logger.error("closed-lid helper uninstall failed; error=\(error.localizedDescription, privacy: .public)")
            showAlert(title: "Could Not Uninstall Closed-Lid Helper", message: error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func terminateDuplicateInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let duplicate = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentPID && !$0.isTerminated }

        if duplicate {
            logger.notice("duplicate app instance detected; terminating this instance")
            NSApp.terminate(nil)
        }

        return duplicate
    }

    private func configureStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func configurePreferenceNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: AppPreferences.didChangeNotification,
            object: nil
        )
    }

    private func configureWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(agentAppDidLaunch),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(agentAppDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        lastRenderedState = nil
        refresh()
    }

    private func primeCPUHistoryThenRefresh() {
        guard monitoringEnabled else {
            refresh()
            return
        }

        _ = scanner.scan()
        renderCheckingState()

        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.refresh()
        }.tolerance = 0.25
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        let holding = powerController.isHoldingAssertions ? "yes" : "no"
        wasHoldingAssertionsAtSleep = powerController.isHoldingAssertions
        logger.notice(
            "system will sleep; holding=\(holding, privacy: .public) activity=\(self.activityLogState, privacy: .public)"
        )
    }

    @objc private func systemDidWake(_ notification: Notification) {
        logger.notice("system did wake")
        scanner.resetCPUHistory()
        let shouldRevalidateAfterWake = wasHoldingAssertionsAtSleep
        wasHoldingAssertionsAtSleep = false

        if monitoringEnabled && shouldRevalidateAfterWake {
            postWakeRevalidationUntil = Date().addingTimeInterval(postWakeRevalidationSeconds)
            logger.notice(
                "post-wake revalidation hold started; seconds=\(self.postWakeRevalidationSeconds, privacy: .public)"
            )
        }

        refresh()
    }

    @objc private func agentAppDidLaunch(_ notification: Notification) {
        guard let app = watchedApplication(from: notification) else {
            return
        }

        logger.notice(
            "agent app launched; bundleID=\(app.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        primeCPUHistoryThenRefresh()
    }

    @objc private func agentAppDidTerminate(_ notification: Notification) {
        guard let app = watchedApplication(from: notification) else {
            return
        }

        logger.notice(
            "agent app terminated; bundleID=\(app.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        refresh()
    }

    private func refresh() {
        if monitoringEnabled {
            let processes = scanner.scan()
            activeCLISessions = cliSessionStore.activeSessions()
            lastReport = activityReport(from: processes, cliSessions: activeCLISessions)
        } else {
            activeCLISessions = []
            lastReport = AgentActivityReport(sessions: [])
        }

        updatePowerState()
        updateStatusItem()
        updateAutomaticQuitCandidate()
        scheduleNextRefresh()
        quitAutomaticallyIfReady()
    }

    private func activityReport(
        from processes: [ProcessSnapshot],
        cliSessions: [AgentSessionToken]
    ) -> AgentActivityReport {
        var sessions = AgentDetector.report(from: processes).sessions
        let detectedKinds = Set(sessions.map(\.kind))
        let syntheticSessions = cliSessions
            .filter { !detectedKinds.contains($0.kind) }
            .map { session in
                AgentSession(
                    kind: session.kind,
                    root: ProcessSnapshot(
                        pid: session.pid,
                        parentPID: 1,
                        cpuPercent: 0,
                        state: "token",
                        command: "Close Your Laptop CLI session \(session.id)"
                    ),
                    descendants: []
                )
            }

        sessions.append(contentsOf: syntheticSessions)
        return AgentActivityReport(sessions: sessions)
    }

    private func updatePowerState() {
        let now = Date()
        let isHoldingForPostWakeRevalidation = postWakeRevalidationUntil.map { now < $0 } ?? false

        if !isHoldingForPostWakeRevalidation {
            postWakeRevalidationUntil = nil
        }

        if lastReport.isActive {
            lastActiveDate = now
            lastActiveWasDesktopGUI = lastReport.sessions.contains { session in
                AgentDetector.guiKind(for: session.root) != nil
            }
            isHoldingForGracePeriod = false
            postWakeRevalidationUntil = nil
        } else if isHoldingForPostWakeRevalidation {
            isHoldingForGracePeriod = false
        } else if let lastActiveDate {
            let graceSeconds = lastActiveWasDesktopGUI ? desktopReleaseGraceSeconds : releaseGraceSeconds
            isHoldingForGracePeriod = now.timeIntervalSince(lastActiveDate) < graceSeconds
        } else {
            isHoldingForGracePeriod = false
        }

        let shouldHold = monitoringEnabled &&
            (lastReport.isActive || isHoldingForGracePeriod || isHoldingForPostWakeRevalidation)
        let reason: String
        if lastReport.isActive {
            reason = lastReport.summary
        } else if isHoldingForPostWakeRevalidation {
            reason = "Rechecking Claude/Codex after wake."
        } else {
            reason = "Claude/Codex finished recently."
        }
        logActivityStateIfNeeded()

        let wasHoldingAssertions = powerController.isHoldingAssertions
        powerController.setAssertionsEnabled(shouldHold, reason: reason)
        let isHoldingAssertions = powerController.isHoldingAssertions

        if !wasHoldingAssertions && isHoldingAssertions {
            logger.notice("sleep assertions acquired; reason=\(reason, privacy: .public)")
        } else if wasHoldingAssertions && !isHoldingAssertions {
            logger.notice("sleep assertions released; activity=\(self.activityLogState, privacy: .public)")
        } else if shouldHold && !isHoldingAssertions {
            let error = powerController.lastErrorDescription ?? "unknown error"
            logger.error("sleep assertions requested but not held; error=\(error, privacy: .public)")
        }
    }

    private func updateStatusItem(force: Bool = false) {
        let state = RenderedState(
            monitoringEnabled: monitoringEnabled,
            isHoldingAssertions: powerController.isHoldingAssertions,
            headline: headline,
            detailLine: detailLine,
            powerError: powerController.lastErrorDescription,
            clamshellLine: powerController.clamshellStatusLine,
            watcherState: watcherController.installationState(),
            sessionLines: lastReport.sessions.map { session in
                "\(session.kind.displayName) PID \(session.root.pid), \(session.processCount) process\(session.processCount == 1 ? "" : "es")"
            }
        )

        guard force || state != lastRenderedState else {
            return
        }

        lastRenderedState = state
        setStatusPresentation(
            imageName: state.isHoldingAssertions ? "bolt.fill" : "moon.zzz",
            title: state.isHoldingAssertions ? "Awake" : "Sleep OK",
            accessibilityDescription: state.isHoldingAssertions ? "Keeping Mac awake" : "Allowing sleep"
        )
        statusItem.menu = buildMenu(from: state)
    }

    private func renderCheckingState() {
        setStatusPresentation(
            imageName: "moon.zzz",
            title: "Checking",
            accessibilityDescription: "Checking Claude and Codex activity"
        )

        let menu = NSMenu()
        addDisabledItem(title: "Checking Claude/Codex activity.", to: menu)
        addDisabledItem(title: "Measuring recent activity.", to: menu)
        statusItem.menu = menu
    }

    private func scheduleNextRefresh() {
        guard monitoringEnabled else {
            timer?.invalidate()
            timer = nil
            currentRefreshInterval = 0
            return
        }

        let interval: TimeInterval
        if lastReport.isActive || isHoldingForGracePeriod || postWakeRevalidationUntil != nil {
            interval = activeRefreshSeconds
        } else if isWatchedAppRunning {
            interval = idleRefreshSeconds
        } else if automaticQuitCandidateSince != nil {
            interval = min(automaticQuitDelaySeconds, dormantRefreshSeconds)
        } else {
            interval = dormantRefreshSeconds
        }

        guard timer == nil || currentRefreshInterval != interval else {
            return
        }

        timer?.invalidate()
        currentRefreshInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = interval * 0.25
    }

    private func buildMenu(from state: RenderedState) -> NSMenu {
        let menu = NSMenu()

        addDisabledItem(title: state.headline, to: menu)
        addDisabledItem(title: state.detailLine, to: menu)

        if let powerError = state.powerError {
            addDisabledItem(title: powerError, to: menu)
        }

        if let clamshellLine = state.clamshellLine {
            addDisabledItem(title: clamshellLine, to: menu)
        }

        if !state.sessionLines.isEmpty {
            menu.addItem(.separator())
            for sessionLine in state.sessionLines {
                addDisabledItem(title: sessionLine, to: menu)
            }
        }

        menu.addItem(.separator())

        let monitorItem = NSMenuItem(
            title: "Monitor Claude/Codex",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        monitorItem.target = self
        monitorItem.state = monitoringEnabled ? .on : .off
        menu.addItem(monitorItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let watcherItem = NSMenuItem(title: "Tiny Persistent Watcher", action: nil, keyEquivalent: "")
        let watcherMenu = NSMenu(title: "Tiny Persistent Watcher")
        switch state.watcherState {
        case .notInstalled(let canInstall):
            if canInstall {
                addWatcherAction(
                    title: "Install",
                    action: #selector(installTinyPersistentWatcher),
                    to: watcherMenu
                )
            } else {
                addDisabledItem(title: "Move app to Applications to install.", to: watcherMenu)
            }
        case .stale(let canUpdate):
            if canUpdate {
                addWatcherAction(
                    title: "Update",
                    action: #selector(updateTinyPersistentWatcher),
                    to: watcherMenu
                )
            } else {
                addDisabledItem(title: "Current app cannot update watcher.", to: watcherMenu)
            }
            addWatcherAction(
                title: "Uninstall",
                action: #selector(uninstallTinyPersistentWatcher),
                to: watcherMenu
            )
        case .current:
            addWatcherAction(
                title: "Uninstall",
                action: #selector(uninstallTinyPersistentWatcher),
                to: watcherMenu
            )
        }

        watcherItem.submenu = watcherMenu
        menu.addItem(watcherItem)

        addDisabledItem(title: "Battery-first: sleep is allowed as soon as work stops.", to: menu)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Close Your Laptop", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func setStatusPresentation(
        imageName: String,
        title: String,
        accessibilityDescription: String
    ) {
        statusItem.length = AppPreferences.showMenuBarStatusText ? NSStatusItem.variableLength : NSStatusItem.squareLength
        statusItem.button?.imagePosition = AppPreferences.showMenuBarStatusText ? .imageLeading : .imageOnly
        statusItem.button?.image = templateImage(named: imageName, accessibilityDescription: accessibilityDescription)
        statusItem.button?.title = AppPreferences.showMenuBarStatusText ? title : ""
        statusItem.button?.toolTip = title
    }

    private func templateImage(named name: String, accessibilityDescription: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
            .flatMap {
                $0.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: AppPreferences.menuBarIconSize.pointSize, weight: .regular)
                )
            }
        image?.isTemplate = true
        return image
    }

    private func diagnosticsSummary() -> String {
        let diagnostics = UpdateDiagnostics.current()
        return [
            "Close Your Laptop diagnostics",
            "bundle: \(diagnostics.bundlePath)",
            "version: \(diagnostics.version ?? "missing")",
            "build: \(diagnostics.build ?? "missing")",
            "monitoring: \(monitoringEnabled ? "enabled" : "disabled")",
            "menu bar icon: \(AppPreferences.menuBarIconSize.displayName)",
            "menu bar text: \(AppPreferences.showMenuBarStatusText ? "shown" : "hidden")",
            "activity: \(activityLogState)",
            "assertions held: \(powerController.isHoldingAssertions ? "yes" : "no")",
            "clamshell: \(powerController.clamshellStatusLine ?? "inactive")",
            "watcher: \(watcherController.installationState().diagnosticsSummary)",
            "closed-lid helper: \(clamshellHelperController.installationState().diagnosticsSummary)",
            "feed: \(diagnostics.feedURL ?? "missing")",
            "public key: \(diagnostics.publicKey?.isEmpty == false ? "present" : "missing")",
            "automatic checks: \(diagnostics.automaticChecksEnabled ? "enabled" : "disabled")",
            "automatic downloads: \(diagnostics.automaticDownloadsAllowed ? "allowed" : "not allowed")",
            "Sparkle.framework: \(diagnostics.sparkleFrameworkExists ? "present" : "missing")",
            "Installer.xpc: \(diagnostics.sparkleInstallerExists ? "present" : "missing")"
        ].joined(separator: "\n")
    }

    private var headline: String {
        if !monitoringEnabled {
            return "Monitoring is off."
        }

        if powerController.isHoldingAssertions {
            return "Keeping this Mac awake."
        }

        return "Sleep is allowed."
    }

    private var detailLine: String {
        if !monitoringEnabled {
            return "Power assertions are released."
        }

        if lastReport.isActive {
            return lastReport.summary
        }

        if isHoldingForGracePeriod {
            if lastActiveWasDesktopGUI {
                return "Verifying the desktop agent really finished."
            }

            return "Releasing shortly after the last agent exits."
        }

        if postWakeRevalidationUntil != nil {
            return "Rechecking Claude/Codex after wake."
        }

        if !isWatchedAppRunning && activeCLISessions.isEmpty {
            return "No Claude or Codex apps or CLI sessions are running."
        }

        if isWatchedAppRunning {
            return "Claude or Codex is open, but no work is active."
        }

        return "No Claude or Codex work is active."
    }

    private var activityLogState: String {
        if !monitoringEnabled {
            return "monitoring-off"
        }

        if lastReport.isActive {
            return "active: \(lastReport.summary)"
        }

        if postWakeRevalidationUntil != nil {
            return "post-wake-recheck"
        }

        if isHoldingForGracePeriod {
            return "release-grace"
        }

        if !isWatchedAppRunning && activeCLISessions.isEmpty {
            return "dormant"
        }

        if isWatchedAppRunning {
            return "idle-gui"
        }

        return "idle"
    }

    private var isWatchedAppRunning: Bool {
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

    private func updateAutomaticQuitCandidate(now: Date = Date()) {
        guard shouldQuitAutomatically else {
            automaticQuitCandidateSince = nil
            return
        }

        if automaticQuitCandidateSince == nil {
            automaticQuitCandidateSince = now
            logger.notice(
                "automatic idle quit pending; seconds=\(self.automaticQuitDelaySeconds, privacy: .public)"
            )
        }
    }

    private var shouldQuitAutomatically: Bool {
        automaticQuitEnabled &&
            monitoringEnabled &&
            !isWatchedAppRunning &&
            activeCLISessions.isEmpty &&
            !lastReport.isActive &&
            !isHoldingForGracePeriod &&
            postWakeRevalidationUntil == nil &&
            !powerController.isHoldingAssertions
    }

    private func quitAutomaticallyIfReady(now: Date = Date()) {
        guard let automaticQuitCandidateSince,
              now.timeIntervalSince(automaticQuitCandidateSince) >= automaticQuitDelaySeconds,
              now.timeIntervalSince(launchDate) >= automaticQuitDelaySeconds else {
            return
        }

        logger.notice("automatic idle quit")
        NSApp.terminate(nil)
    }

    private func logActivityStateIfNeeded() {
        let state = activityLogState
        guard state != lastLoggedActivityState else {
            return
        }

        lastLoggedActivityState = state
        logger.notice("activity state changed; state=\(state, privacy: .public)")
    }

    private func addDisabledItem(title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addWatcherAction(title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private struct RenderedState: Equatable {
    let monitoringEnabled: Bool
    let isHoldingAssertions: Bool
    let headline: String
    let detailLine: String
    let powerError: String?
    let clamshellLine: String?
    let watcherState: WatcherInstallationState
    let sessionLines: [String]
}

private extension WatcherInstallationState {
    var diagnosticsSummary: String {
        switch self {
        case .notInstalled(let canInstall):
            return canInstall ? "not installed; installable" : "not installed; app must be in Applications"
        case .stale(let canUpdate):
            return canUpdate ? "stale; updatable" : "stale; not updatable from this app"
        case .current:
            return "current"
        }
    }
}

private extension ClamshellHelperInstallationState {
    var diagnosticsSummary: String {
        switch self {
        case .notInstalled(let canInstall):
            return canInstall ? "not installed; installable" : "not installed; app must be in Applications"
        case .stale(let canUpdate):
            return canUpdate ? "stale; updatable" : "stale; not updatable from this app"
        case .current:
            return "current"
        }
    }
}
