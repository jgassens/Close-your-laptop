import Darwin
import Foundation

final class WatcherController {
    private let fileManager: FileManager
    private let label = "com.gassensmith.closeyourlaptop.watcher"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path) &&
            fileManager.isExecutableFile(atPath: installedWatcherURL.path)
    }

    func install(appBundleURL: URL = Bundle.main.bundleURL) throws {
        guard appBundleURL.standardizedFileURL.path.hasPrefix("/Applications/") else {
            throw WatcherError.appNotInApplications
        }

        guard let bundledWatcherURL = Bundle.main.url(
            forResource: "CloseYourLaptopWatcher",
            withExtension: nil
        ) else {
            throw WatcherError.missingBundledWatcher
        }

        try fileManager.createDirectory(
            at: installDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: launchAgentsDirectoryURL,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: installedWatcherURL.path) {
            try fileManager.removeItem(at: installedWatcherURL)
        }
        try fileManager.copyItem(at: bundledWatcherURL, to: installedWatcherURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: installedWatcherURL.path
        )

        try writeLaunchAgent(appBundleURL: appBundleURL)
        _ = try? runLaunchctl(["bootout", userLaunchdDomain, plistURL.path], allowFailure: true)
        try runLaunchctl(["bootstrap", userLaunchdDomain, plistURL.path])
        try runLaunchctl(["enable", "\(userLaunchdDomain)/\(label)"])
        try runLaunchctl(["kickstart", "-k", "\(userLaunchdDomain)/\(label)"])
    }

    func uninstall() throws {
        _ = try? runLaunchctl(["bootout", userLaunchdDomain, plistURL.path], allowFailure: true)

        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }

        if fileManager.fileExists(atPath: installedWatcherURL.path) {
            try fileManager.removeItem(at: installedWatcherURL)
        }
    }

    private func writeLaunchAgent(appBundleURL: URL) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [installedWatcherURL.path],
            "EnvironmentVariables": [
                "CYL_APP_PATH": appBundleURL.path
            ],
            "RunAtLoad": true,
            "KeepAlive": [
                "SuccessfulExit": false
            ],
            "ProcessType": "Background",
            "StandardOutPath": "/tmp/close-your-laptop-watcher.out",
            "StandardErrorPath": "/tmp/close-your-laptop-watcher.err"
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !allowFailure {
            throw WatcherError.launchctlFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return text
    }

    private var userLaunchdDomain: String {
        "gui/\(getuid())"
    }

    private var applicationSupportURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    private var installDirectoryURL: URL {
        applicationSupportURL
            .appendingPathComponent("Close Your Laptop", isDirectory: true)
    }

    private var installedWatcherURL: URL {
        installDirectoryURL
            .appendingPathComponent("CloseYourLaptopWatcher", isDirectory: false)
    }

    private var launchAgentsDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectoryURL
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }
}

enum WatcherError: LocalizedError {
    case missingBundledWatcher
    case appNotInApplications
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledWatcher:
            return "CloseYourLaptopWatcher is missing from this app bundle."
        case .appNotInApplications:
            return "Move Close Your Laptop to Applications before installing the watcher."
        case .launchctlFailed(let message):
            return message.isEmpty ? "launchctl failed." : message
        }
    }
}
