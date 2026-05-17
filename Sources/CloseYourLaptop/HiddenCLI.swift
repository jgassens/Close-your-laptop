import CloseYourLaptopCore
import Foundation

enum HiddenCLI {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        let args = Array(arguments.dropFirst())
        guard let command = args.first else {
            return nil
        }

        switch command {
        case "--scan-once":
            runScan(twice: false)
            return EXIT_SUCCESS
        case "--scan-twice":
            runScan(twice: true)
            return EXIT_SUCCESS
        case "--update-diagnostics":
            runUpdateDiagnostics(json: args.contains("--json"))
            return EXIT_SUCCESS
        case "--check-appcast":
            return runCheckAppcast(arguments: Array(args.dropFirst()))
        case "--print-appcast":
            return runPrintAppcast(arguments: Array(args.dropFirst()))
        case "--sparkle-tools":
            runSparkleTools()
            return EXIT_SUCCESS
        case "--sign-update":
            return runSignUpdate(arguments: Array(args.dropFirst()))
        default:
            return nil
        }
    }

    private static func runScan(twice: Bool) {
        let scanner = ProcessScanner()
        if twice {
            _ = scanner.scan()
            Thread.sleep(forTimeInterval: 2)
        }

        let report = AgentDetector.report(from: scanner.scan())
        print(report.summary)

        for session in report.sessions {
            print("\(session.kind.displayName) pid=\(session.root.pid) processes=\(session.processCount)")
        }
    }

    private static func runUpdateDiagnostics(json: Bool) {
        let diagnostics = UpdateDiagnostics.current()
        if json {
            let interval = diagnostics.scheduledCheckInterval.map { String($0) } ?? "null"
            let lines = [
                "\"bundlePath\": \"\(jsonEscape(diagnostics.bundlePath))\"",
                "\"version\": \(jsonString(diagnostics.version))",
                "\"build\": \(jsonString(diagnostics.build))",
                "\"feedURL\": \(jsonString(diagnostics.feedURL))",
                "\"publicKeyPresent\": \(diagnostics.publicKey?.isEmpty == false)",
                "\"automaticChecksEnabled\": \(diagnostics.automaticChecksEnabled)",
                "\"automaticDownloadsAllowed\": \(diagnostics.automaticDownloadsAllowed)",
                "\"scheduledCheckInterval\": \(interval)",
                "\"sparkleFrameworkExists\": \(diagnostics.sparkleFrameworkExists)",
                "\"sparkleInstallerExists\": \(diagnostics.sparkleInstallerExists)",
                "\"sparkleConfigured\": \(diagnostics.isSparkleConfigured)"
            ]
            print("{\n  " + lines.joined(separator: ",\n  ") + "\n}")
            return
        }

        print("bundle: \(diagnostics.bundlePath)")
        print("version: \(diagnostics.version ?? "missing")")
        print("build: \(diagnostics.build ?? "missing")")
        print("feed: \(diagnostics.feedURL ?? "missing")")
        print("public key: \(diagnostics.publicKey?.isEmpty == false ? "present" : "missing")")
        print("automatic checks: \(diagnostics.automaticChecksEnabled ? "enabled" : "disabled")")
        print("automatic downloads: \(diagnostics.automaticDownloadsAllowed ? "allowed" : "not allowed")")
        print("interval: \(diagnostics.scheduledCheckInterval.map { "\(Int($0))s" } ?? "missing")")
        print("Sparkle.framework: \(diagnostics.sparkleFrameworkExists ? "present" : "missing")")
        print("Installer.xpc: \(diagnostics.sparkleInstallerExists ? "present" : "missing")")
        print("configured: \(diagnostics.isSparkleConfigured ? "yes" : "no - \(diagnostics.configurationProblem)")")
    }

    private static func runCheckAppcast(arguments: [String]) -> Int32 {
        let parsed = ParsedArguments(arguments)
        let urlString = parsed.value(after: "--url") ?? UpdateDiagnostics.current().feedURL

        guard let urlString, let url = URL(string: urlString) else {
            fputs("missing or invalid appcast URL\n", stderr)
            return EXIT_FAILURE
        }

        do {
            let data = try fetch(url: url)
            let parser = AppcastSummaryParser()
            let item = try parser.parse(data: data)
            print("feed: \(url.absoluteString)")
            print("bytes: \(data.count)")
            print("title: \(item.title ?? "missing")")
            print("version: \(item.version ?? "missing")")
            print("short version: \(item.shortVersion ?? "missing")")
            print("download: \(item.downloadURL ?? "missing")")
            print("signature: \(item.signature?.isEmpty == false ? "present" : "missing")")
            print("release notes: \(item.releaseNotesURL ?? "inline or missing")")
            return EXIT_SUCCESS
        } catch {
            fputs("appcast check failed: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func runPrintAppcast(arguments: [String]) -> Int32 {
        let parsed = ParsedArguments(arguments)
        guard let version = parsed.value(after: "--version"),
              let shortVersion = parsed.value(after: "--short-version"),
              let downloadURL = parsed.value(after: "--download-url"),
              let signature = parsed.value(after: "--ed-signature"),
              let length = parsed.value(after: "--length") else {
            fputs("missing required appcast fields\n", stderr)
            return EXIT_FAILURE
        }

        let title = parsed.value(after: "--title") ?? "Close Your Laptop \(shortVersion)"
        let summary = parsed.value(after: "--summary") ?? "Maintenance update."
        let releaseNotesURL = parsed.value(after: "--release-notes-url")
        let minimumSystemVersion = parsed.value(after: "--minimum-system-version") ?? "13.0"
        let pubDate = parsed.value(after: "--pub-date") ?? httpDate(Date())

        print(appcastXML(
            title: title,
            version: version,
            shortVersion: shortVersion,
            downloadURL: downloadURL,
            signature: signature,
            length: length,
            summary: summary,
            releaseNotesURL: releaseNotesURL,
            minimumSystemVersion: minimumSystemVersion,
            pubDate: pubDate
        ))
        return EXIT_SUCCESS
    }

    private static func runSparkleTools() {
        let root = FileManager.default.currentDirectoryPath
        let artifactRoot = "\(root)/.build/artifacts/sparkle/Sparkle"
        let tools = [
            "generate_keys": "\(artifactRoot)/bin/generate_keys",
            "sign_update": "\(artifactRoot)/bin/sign_update",
            "Sparkle.framework": "\(artifactRoot)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        ]

        for (name, path) in tools.sorted(by: { $0.key < $1.key }) {
            let exists = FileManager.default.fileExists(atPath: path) ? "present" : "missing"
            print("\(name): \(path) (\(exists))")
        }
    }

    private static func runSignUpdate(arguments: [String]) -> Int32 {
        let parsed = ParsedArguments(arguments)
        guard let archivePath = parsed.value(after: "--archive") else {
            fputs("missing --archive path\n", stderr)
            return EXIT_FAILURE
        }

        let signUpdate = "\(FileManager.default.currentDirectoryPath)/.build/artifacts/sparkle/Sparkle/bin/sign_update"
        guard FileManager.default.fileExists(atPath: signUpdate) else {
            fputs("Sparkle sign_update tool is missing; run swift package resolve first\n", stderr)
            return EXIT_FAILURE
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: signUpdate)
        process.arguments = [archivePath]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                print(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return process.terminationStatus
        } catch {
            fputs("sign_update failed: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func fetch(url: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result = .failure(error)
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode) {
                result = .failure(CLIError.httpStatus(httpResponse.statusCode))
                return
            }

            result = .success(data ?? Data())
        }
        task.resume()
        semaphore.wait()
        return try result.get()
    }

    private static func appcastXML(
        title: String,
        version: String,
        shortVersion: String,
        downloadURL: String,
        signature: String,
        length: String,
        summary: String,
        releaseNotesURL: String?,
        minimumSystemVersion: String,
        pubDate: String
    ) -> String {
        let releaseNotesLine = releaseNotesURL.map {
            "      <sparkle:releaseNotesLink>\(xmlEscape($0))</sparkle:releaseNotesLink>\n"
        } ?? ""

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Close Your Laptop Updates</title>
            <item>
              <title>\(xmlEscape(title))</title>
              <sparkle:version>\(xmlEscape(version))</sparkle:version>
              <sparkle:shortVersionString>\(xmlEscape(shortVersion))</sparkle:shortVersionString>
              <description><![CDATA[\(summary)]]></description>
        \(releaseNotesLine)      <pubDate>\(xmlEscape(pubDate))</pubDate>
              <sparkle:minimumSystemVersion>\(xmlEscape(minimumSystemVersion))</sparkle:minimumSystemVersion>
              <enclosure
                url="\(xmlEscape(downloadURL))"
                length="\(xmlEscape(length))"
                type="application/octet-stream"
                sparkle:edSignature="\(xmlEscape(signature))" />
            </item>
          </channel>
        </rss>
        """
    }

    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func jsonString(_ value: String?) -> String {
        guard let value else {
            return "null"
        }

        return "\"\(jsonEscape(value))\""
    }

    private static func jsonEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

private struct ParsedArguments {
    let arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    func value(after key: String) -> String? {
        guard let index = arguments.firstIndex(of: key) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return arguments[valueIndex]
    }
}

private struct AppcastItemSummary {
    var title: String?
    var version: String?
    var shortVersion: String?
    var downloadURL: String?
    var signature: String?
    var releaseNotesURL: String?
}

private final class AppcastSummaryParser: NSObject, XMLParserDelegate {
    private var summary = AppcastItemSummary()
    private var currentElement: String?
    private var currentText = ""
    private var insideFirstItem = false
    private var finishedFirstItem = false

    func parse(data: Data) throws -> AppcastItemSummary {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? CLIError.invalidAppcast
        }

        return summary
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !finishedFirstItem else {
            return
        }

        if elementName == "item" {
            insideFirstItem = true
        }

        guard insideFirstItem else {
            return
        }

        currentElement = elementName
        currentText = ""

        if elementName == "enclosure" {
            summary.version = summary.version ?? attributeDict["sparkle:version"]
            summary.shortVersion = summary.shortVersion ?? attributeDict["sparkle:shortVersionString"]
            summary.downloadURL = attributeDict["url"]
            summary.signature = attributeDict["sparkle:edSignature"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideFirstItem, currentElement != nil else {
            return
        }

        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard insideFirstItem else {
            return
        }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "title", summary.title == nil {
            summary.title = trimmed
        } else if elementName == "version" || elementName == "sparkle:version" {
            summary.version = trimmed
        } else if elementName == "shortVersionString" || elementName == "sparkle:shortVersionString" {
            summary.shortVersion = trimmed
        } else if elementName == "releaseNotesLink" || elementName == "sparkle:releaseNotesLink" {
            summary.releaseNotesURL = trimmed
        } else if elementName == "item" {
            insideFirstItem = false
            finishedFirstItem = true
        }

        currentElement = nil
        currentText = ""
    }
}

private enum CLIError: LocalizedError {
    case httpStatus(Int)
    case invalidAppcast

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .invalidAppcast:
            return "invalid appcast"
        }
    }
}
