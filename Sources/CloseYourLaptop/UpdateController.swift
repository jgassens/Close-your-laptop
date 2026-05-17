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
}
