import AppKit

final class PreferencesWindowController: NSWindowController {
    private let onRefresh: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onInstallClamshellHelper: () -> Void
    private let onUninstallClamshellHelper: () -> Void
    private let diagnosticsProvider: () -> String
    private let watcherStateProvider: () -> WatcherInstallationState
    private let clamshellHelperStateProvider: () -> ClamshellHelperInstallationState

    private let monitorCheckbox = NSButton(
        checkboxWithTitle: "Monitor Claude/Codex work",
        target: nil,
        action: nil
    )
    private let statusTextCheckbox = NSButton(
        checkboxWithTitle: "Show status text in the menu bar",
        target: nil,
        action: nil
    )
    private let iconSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let watcherStatusLabel = NSTextField(labelWithString: "")
    private let clamshellHelperStatusLabel = NSTextField(labelWithString: "")
    private let clamshellHelperPrimaryButton = NSButton(title: "Install", target: nil, action: nil)
    private let clamshellHelperUninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
    private let feedURLLabel = NSTextField(labelWithString: "")
    private let copiedLabel = NSTextField(labelWithString: "")

    init(
        onRefresh: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onInstallClamshellHelper: @escaping () -> Void,
        onUninstallClamshellHelper: @escaping () -> Void,
        diagnosticsProvider: @escaping () -> String,
        watcherStateProvider: @escaping () -> WatcherInstallationState,
        clamshellHelperStateProvider: @escaping () -> ClamshellHelperInstallationState
    ) {
        self.onRefresh = onRefresh
        self.onCheckForUpdates = onCheckForUpdates
        self.onInstallClamshellHelper = onInstallClamshellHelper
        self.onUninstallClamshellHelper = onUninstallClamshellHelper
        self.diagnosticsProvider = diagnosticsProvider
        self.watcherStateProvider = watcherStateProvider
        self.clamshellHelperStateProvider = clamshellHelperStateProvider

        super.init(window: nil)

        window = makeWindow()
        refreshControls()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: AppPreferences.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func showWindow(_ sender: Any?) {
        refreshControls()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible == false {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])

        stack.addArrangedSubview(sectionTitle("Menu Bar"))

        iconSizePopup.addItems(withTitles: MenuBarIconSize.allCases.map(\.displayName))
        iconSizePopup.target = self
        iconSizePopup.action = #selector(iconSizeChanged)

        let iconRow = labeledControl(title: "Icon size", control: iconSizePopup)
        stack.addArrangedSubview(iconRow)

        statusTextCheckbox.target = self
        statusTextCheckbox.action = #selector(statusTextChanged)
        stack.addArrangedSubview(statusTextCheckbox)

        monitorCheckbox.target = self
        monitorCheckbox.action = #selector(monitoringChanged)
        stack.addArrangedSubview(monitorCheckbox)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Watcher"))
        watcherStatusLabel.lineBreakMode = .byWordWrapping
        watcherStatusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(watcherStatusLabel)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Closed-Lid Helper"))
        clamshellHelperStatusLabel.lineBreakMode = .byWordWrapping
        clamshellHelperStatusLabel.maximumNumberOfLines = 3
        stack.addArrangedSubview(clamshellHelperStatusLabel)

        clamshellHelperPrimaryButton.target = self
        clamshellHelperPrimaryButton.action = #selector(installClamshellHelper)
        clamshellHelperPrimaryButton.bezelStyle = .rounded

        clamshellHelperUninstallButton.target = self
        clamshellHelperUninstallButton.action = #selector(uninstallClamshellHelper)
        clamshellHelperUninstallButton.bezelStyle = .rounded

        let clamshellHelperRow = NSStackView(views: [
            clamshellHelperPrimaryButton,
            clamshellHelperUninstallButton
        ])
        clamshellHelperRow.orientation = .horizontal
        clamshellHelperRow.alignment = .centerY
        clamshellHelperRow.spacing = 10
        stack.addArrangedSubview(clamshellHelperRow)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Updates"))

        feedURLLabel.lineBreakMode = .byTruncatingMiddle
        feedURLLabel.isSelectable = true
        stack.addArrangedSubview(feedURLLabel)

        let updateButton = NSButton(
            title: "Check for Updates...",
            target: self,
            action: #selector(checkForUpdates)
        )
        updateButton.bezelStyle = .rounded
        stack.addArrangedSubview(updateButton)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Diagnostics"))

        let refreshButton = NSButton(title: "Refresh Now", target: self, action: #selector(refreshNow))
        refreshButton.bezelStyle = .rounded

        let copyButton = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnostics))
        copyButton.bezelStyle = .rounded

        let diagnosticsRow = NSStackView(views: [refreshButton, copyButton, copiedLabel])
        diagnosticsRow.orientation = .horizontal
        diagnosticsRow.alignment = .centerY
        diagnosticsRow.spacing = 10
        stack.addArrangedSubview(diagnosticsRow)

        let cadenceLabel = NSTextField(
            labelWithString: "Refresh cadence: active 5s, open-but-idle 15s, dormant 60s."
        )
        cadenceLabel.textColor = .secondaryLabelColor
        cadenceLabel.lineBreakMode = .byWordWrapping
        cadenceLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(cadenceLabel)

        copiedLabel.textColor = .secondaryLabelColor

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Close Your Laptop Preferences"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 460, height: 450)
        return window
    }

    private func refreshControls() {
        monitorCheckbox.state = AppPreferences.monitoringEnabled ? .on : .off
        statusTextCheckbox.state = AppPreferences.showMenuBarStatusText ? .on : .off
        iconSizePopup.selectItem(withTitle: AppPreferences.menuBarIconSize.displayName)

        watcherStatusLabel.stringValue = "Tiny persistent watcher: \(watcherStateProvider().preferencesSummary)"
        refreshClamshellHelperControls()

        let diagnostics = UpdateDiagnostics.current()
        feedURLLabel.stringValue = "Sparkle feed: \(diagnostics.feedURL ?? "missing")"
        copiedLabel.stringValue = ""
    }

    private func refreshClamshellHelperControls() {
        let state = clamshellHelperStateProvider()
        clamshellHelperStatusLabel.stringValue = "Closed-lid helper: \(state.preferencesSummary)"

        switch state {
        case .notInstalled(let canInstall):
            clamshellHelperPrimaryButton.title = "Install Helper"
            clamshellHelperPrimaryButton.isEnabled = canInstall
            clamshellHelperUninstallButton.isHidden = true
        case .stale(let canUpdate):
            clamshellHelperPrimaryButton.title = "Update Helper"
            clamshellHelperPrimaryButton.isEnabled = canUpdate
            clamshellHelperUninstallButton.isHidden = false
            clamshellHelperUninstallButton.isEnabled = true
        case .current:
            clamshellHelperPrimaryButton.title = "Helper Current"
            clamshellHelperPrimaryButton.isEnabled = false
            clamshellHelperUninstallButton.isHidden = false
            clamshellHelperUninstallButton.isEnabled = true
        }
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func labeledControl(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    @objc private func monitoringChanged() {
        AppPreferences.monitoringEnabled = monitorCheckbox.state == .on
        postPreferencesChanged()
    }

    @objc private func statusTextChanged() {
        AppPreferences.showMenuBarStatusText = statusTextCheckbox.state == .on
        postPreferencesChanged()
    }

    @objc private func iconSizeChanged() {
        guard let title = iconSizePopup.selectedItem?.title,
              let size = MenuBarIconSize.allCases.first(where: { $0.displayName == title }) else {
            return
        }

        AppPreferences.menuBarIconSize = size
        postPreferencesChanged()
    }

    @objc private func refreshNow() {
        onRefresh()
        refreshControls()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func installClamshellHelper() {
        onInstallClamshellHelper()
        refreshControls()
    }

    @objc private func uninstallClamshellHelper() {
        onUninstallClamshellHelper()
        refreshControls()
    }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsProvider(), forType: .string)
        copiedLabel.stringValue = "Copied"
    }

    @objc private func preferencesDidChange() {
        refreshControls()
    }

    private func postPreferencesChanged() {
        NotificationCenter.default.post(name: AppPreferences.didChangeNotification, object: self)
    }
}

private extension WatcherInstallationState {
    var preferencesSummary: String {
        switch self {
        case .notInstalled(let canInstall):
            return canInstall ? "not installed; ready to install from this app." : "not installed; move the app to Applications first."
        case .stale(let canUpdate):
            return canUpdate ? "installed but stale; update it from the menu." : "installed but stale; current app cannot update it."
        case .current:
            return "installed and current."
        }
    }
}

private extension ClamshellHelperInstallationState {
    var preferencesSummary: String {
        switch self {
        case .notInstalled(let canInstall):
            return canInstall ? "not installed. Install once to avoid password prompts on app launch." : "not installed; move the app to Applications first."
        case .stale(let canUpdate):
            return canUpdate ? "installed but stale. Update only when the helper protocol changes." : "installed but stale; current app cannot update it."
        case .current:
            return "installed and current. App launches will only write heartbeats."
        }
    }
}
