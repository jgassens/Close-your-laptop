import Foundation
import OSLog
import Sparkle

final class UpdateController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gassensmith.closeyourlaptop",
        category: "Update"
    )

    private var updaterController: SPUStandardUpdaterController?

    func start() {
        MainActor.assumeIsolated {
            guard updaterController == nil else {
                return
            }

            let diagnostics = UpdateDiagnostics.current()
            guard diagnostics.isSparkleConfigured else {
                logger.error("sparkle updater not started; \(diagnostics.configurationProblem, privacy: .public)")
                return
            }

            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            logger.notice("sparkle updater started; feed=\(diagnostics.feedURL ?? "missing", privacy: .public)")
        }
    }

    func checkForUpdates(reportProblem: @escaping (String) -> Void) {
        MainActor.assumeIsolated {
            if updaterController == nil {
                start()
            }

            guard let updaterController else {
                let diagnostics = UpdateDiagnostics.current()
                reportProblem(diagnostics.configurationProblem)
                return
            }

            let diagnostics = UpdateDiagnostics.current()
            guard let feedURLString = diagnostics.feedURL,
                  let feedURL = URL(string: feedURLString) else {
                reportProblem(diagnostics.configurationProblem)
                return
            }

            preflightAppcast(feedURL) { [weak self, weak updaterController] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        guard let updaterController else {
                            reportProblem("Sparkle updater is no longer available.")
                            return
                        }

                        updaterController.checkForUpdates(nil)
                        self?.logger.notice("manual sparkle update check requested")
                    case .failure(let error):
                        self?.logger.error("manual sparkle appcast preflight failed; error=\(error.localizedDescription, privacy: .public)")
                        reportProblem(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func preflightAppcast(_ url: URL, completion: @escaping (Result<Void, AppcastPreflightError>) -> Void) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(url: url, underlying: error)))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode) {
                completion(.failure(.httpStatus(url: url, statusCode: httpResponse.statusCode)))
                return
            }

            guard data?.isEmpty == false else {
                completion(.failure(.empty(url: url)))
                return
            }

            completion(.success(()))
        }
        task.resume()
    }
}

private enum AppcastPreflightError: LocalizedError {
    case httpStatus(url: URL, statusCode: Int)
    case empty(url: URL)
    case network(url: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let url, let statusCode):
            return "Sparkle appcast is not reachable at \(url.absoluteString) (HTTP \(statusCode)). Publish appcast.xml to the configured GitHub Pages URL, then try again."
        case .empty(let url):
            return "Sparkle appcast at \(url.absoluteString) is empty."
        case .network(let url, let underlying):
            return "Sparkle appcast at \(url.absoluteString) could not be reached: \(underlying.localizedDescription)"
        }
    }
}
