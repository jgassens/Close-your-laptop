import Foundation

struct UpdateDiagnostics: Equatable {
    let bundlePath: String
    let version: String?
    let build: String?
    let feedURL: String?
    let publicKey: String?
    let automaticChecksEnabled: Bool
    let automaticDownloadsAllowed: Bool
    let scheduledCheckInterval: TimeInterval?
    let sparkleFrameworkExists: Bool
    let sparkleInstallerExists: Bool

    var isSparkleConfigured: Bool {
        feedURL.flatMap(URL.init(string:)) != nil &&
            publicKey?.isEmpty == false
    }

    var configurationProblem: String {
        if feedURL.flatMap(URL.init(string:)) == nil {
            return "SUFeedURL is missing or invalid"
        }

        if publicKey?.isEmpty != false {
            return "SUPublicEDKey is missing"
        }

        return "no configuration problem found"
    }

    static func current(bundle: Bundle = .main) -> UpdateDiagnostics {
        let info = bundle.infoDictionary ?? [:]
        let frameworkURL = bundle.bundleURL
            .appendingPathComponent("Contents/Frameworks/Sparkle.framework")
        let installerURLs = [
            frameworkURL.appendingPathComponent("Versions/B/XPCServices/Installer.xpc"),
            frameworkURL.appendingPathComponent("XPCServices/Installer.xpc")
        ]

        return UpdateDiagnostics(
            bundlePath: bundle.bundleURL.path,
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            feedURL: info["SUFeedURL"] as? String,
            publicKey: info["SUPublicEDKey"] as? String,
            automaticChecksEnabled: (info["SUEnableAutomaticChecks"] as? Bool) ?? false,
            automaticDownloadsAllowed: (info["SUAllowsAutomaticUpdates"] as? Bool) ?? true,
            scheduledCheckInterval: info["SUScheduledCheckInterval"] as? TimeInterval,
            sparkleFrameworkExists: FileManager.default.fileExists(atPath: frameworkURL.path),
            sparkleInstallerExists: installerURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
        )
    }
}

