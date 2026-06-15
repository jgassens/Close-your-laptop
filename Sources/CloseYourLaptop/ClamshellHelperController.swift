import Foundation

final class ClamshellHelperController {
    private let fileManager: FileManager
    private let label = "com.gassensmith.closeyourlaptop.clamshell-helper"
    private let productName = "CloseYourLaptopClamshellHelper"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: installedHelperURL.path) &&
            fileManager.fileExists(atPath: plistURL.path)
    }

    func installationState(appBundleURL: URL = Bundle.main.bundleURL) -> ClamshellHelperInstallationState {
        let plistExists = fileManager.fileExists(atPath: plistURL.path)
        let helperInstalled = fileManager.isExecutableFile(atPath: installedHelperURL.path)

        guard plistExists || helperInstalled else {
            return .notInstalled(canInstall: canInstall(from: appBundleURL))
        }

        guard plistExists && helperInstalled else {
            return .stale(canUpdate: canInstall(from: appBundleURL))
        }

        guard let bundledHelperURL else {
            return .stale(canUpdate: false)
        }

        guard launchDaemonProgramPath == installedHelperURL.path,
              helperBinaryMatchesBundledHelper(bundledHelperURL) else {
            return .stale(canUpdate: canInstall(from: appBundleURL))
        }

        return .current
    }

    func install(appBundleURL: URL = Bundle.main.bundleURL) throws {
        guard canInstall(from: appBundleURL) else {
            throw ClamshellHelperError.missingBundledHelper
        }

        guard let bundledHelperURL else {
            throw ClamshellHelperError.missingBundledHelper
        }

        let script = installScript(bundledHelperURL: bundledHelperURL)
        try runAdministratorScript(
            script,
            prompt: "Close Your Laptop needs administrator approval to install its stable closed-lid helper."
        )
    }

    func uninstall() throws {
        let script = """
        /bin/launchctl bootout system \(shellSingleQuoted(plistURL.path)) >/dev/null 2>&1 || true
        /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true
        /bin/rm -f \(shellSingleQuoted(plistURL.path))
        /bin/rm -f \(shellSingleQuoted(installedHelperURL.path))
        """
        try runAdministratorScript(
            script,
            prompt: "Close Your Laptop needs administrator approval to remove its closed-lid helper."
        )
    }

    private var bundledHelperURL: URL? {
        Bundle.main.url(forResource: productName, withExtension: nil)
    }

    private var installedHelperURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools", isDirectory: true)
            .appendingPathComponent(productName, isDirectory: false)
    }

    private var plistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    private func canInstall(from appBundleURL: URL) -> Bool {
        appBundleURL.standardizedFileURL.path.hasPrefix("/Applications/") &&
            bundledHelperURL != nil
    }

    private var launchDaemonProgramPath: String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let arguments = dictionary["ProgramArguments"] as? [String],
              let path = arguments.first else {
            return nil
        }

        return path
    }

    private func helperBinaryMatchesBundledHelper(_ bundledHelperURL: URL) -> Bool {
        guard let installedData = try? Data(contentsOf: installedHelperURL),
              let bundledData = try? Data(contentsOf: bundledHelperURL) else {
            return false
        }

        return installedData == bundledData
    }

    private func installScript(bundledHelperURL: URL) -> String {
        let plist = launchDaemonPlist()
        let launchdService = shellSingleQuoted("system/\(label)")
        return """
        /bin/mkdir -p /Library/PrivilegedHelperTools
        /usr/bin/ditto --noextattr --noqtn --norsrc \(shellSingleQuoted(bundledHelperURL.path)) \(shellSingleQuoted(installedHelperURL.path))
        /usr/sbin/chown root:wheel \(shellSingleQuoted(installedHelperURL.path))
        /bin/chmod 755 \(shellSingleQuoted(installedHelperURL.path))
        /bin/cat > \(shellSingleQuoted(plistURL.path)) <<'PLIST'
        \(plist)
        PLIST
        /usr/sbin/chown root:wheel \(shellSingleQuoted(plistURL.path))
        /bin/chmod 644 \(shellSingleQuoted(plistURL.path))
        /bin/launchctl bootout system \(shellSingleQuoted(plistURL.path)) >/dev/null 2>&1 || true
        /bin/launchctl bootstrap system \(shellSingleQuoted(plistURL.path))
        /bin/launchctl enable \(launchdService)
        /bin/launchctl kickstart -k \(launchdService)
        """
    }

    private func launchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(installedHelperURL.path)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>ProcessType</key>
          <string>Background</string>
          <key>StandardOutPath</key>
          <string>/var/log/close-your-laptop-clamshell-helper.out</string>
          <key>StandardErrorPath</key>
          <string>/var/log/close-your-laptop-clamshell-helper.err</string>
        </dict>
        </plist>
        """
    }

    private func runAdministratorScript(_ script: String, prompt: String) throws {
        let appleScript = "do shell script \(appleScriptLiteral(script)) with administrator privileges with prompt \(appleScriptLiteral(prompt))"
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ClamshellHelperError.administratorScriptFailed(
                message ?? "osascript exited \(process.terminationStatus)"
            )
        }
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

enum ClamshellHelperInstallationState: Equatable {
    case notInstalled(canInstall: Bool)
    case stale(canUpdate: Bool)
    case current
}

enum ClamshellHelperError: LocalizedError {
    case missingBundledHelper
    case administratorScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledHelper:
            return "CloseYourLaptopClamshellHelper is missing from this app bundle."
        case .administratorScriptFailed(let message):
            return message.isEmpty ? "administrator approval was not granted" : message
        }
    }
}
