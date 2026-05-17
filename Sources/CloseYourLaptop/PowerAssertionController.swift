import Foundation
import IOKit
import IOKit.pwr_mgt

final class PowerAssertionController {
    private var idleSleepAssertion: IOPMAssertionID = 0
    private var systemSleepAssertion: IOPMAssertionID = 0
    private let clamshellController = ClamshellSleepController()

    private var assertionErrorDescription: String?

    var isHoldingAssertions: Bool {
        idleSleepAssertion != 0 || systemSleepAssertion != 0
    }

    var clamshellStatusLine: String? {
        clamshellController.statusLine
    }

    var lastErrorDescription: String? {
        assertionErrorDescription ?? clamshellController.lastErrorDescription
    }

    func setAssertionsEnabled(_ enabled: Bool, reason: String) {
        if enabled {
            acquire(reason: reason)
        } else {
            releaseAssertions()
            clamshellController.setEnabled(false, reason: reason)
            assertionErrorDescription = nil
        }
    }

    func releaseAll() {
        releaseAssertions()
        clamshellController.shutdown()
        assertionErrorDescription = nil
    }

    private func releaseAssertions() {
        release(&idleSleepAssertion)
        release(&systemSleepAssertion)
    }

    private func acquire(reason: String) {
        assertionErrorDescription = nil

        if idleSleepAssertion == 0 {
            idleSleepAssertion = createAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                reason: reason
            )
        }

        if systemSleepAssertion == 0 {
            systemSleepAssertion = createAssertion(
                type: kIOPMAssertionTypePreventSystemSleep as CFString,
                reason: reason
            )
        }

        clamshellController.setEnabled(true, reason: reason)
    }

    private func createAssertion(type: CFString, reason: String) -> IOPMAssertionID {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionErrorDescription = "IOKit power assertion failed with code \(result)."
            return 0
        }

        return assertionID
    }

    private func release(_ assertionID: inout IOPMAssertionID) {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
