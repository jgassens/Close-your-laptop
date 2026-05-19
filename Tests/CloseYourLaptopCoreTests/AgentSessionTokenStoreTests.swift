import XCTest
@testable import CloseYourLaptopCore

final class AgentSessionTokenStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testBeginsAndEndsSession() throws {
        let store = AgentSessionTokenStore(directoryURL: temporaryDirectory)
        let pid = Int32(ProcessInfo.processInfo.processIdentifier)

        try store.begin(kind: .codex, token: "codex.test", pid: pid)

        let session = try XCTUnwrap(store.activeSessions().first)
        XCTAssertEqual(session.id, "codex.test")
        XCTAssertEqual(session.kind, .codex)
        XCTAssertEqual(session.pid, pid)

        try store.end(token: "codex.test")

        XCTAssertTrue(store.activeSessions().isEmpty)
    }

    func testPrunesDeadSessionProcess() throws {
        let store = AgentSessionTokenStore(directoryURL: temporaryDirectory)

        try store.begin(kind: .claude, token: "claude.dead", pid: 999_999)

        XCTAssertTrue(store.activeSessions().isEmpty)
    }

    func testSanitizesUnsafeTokenCharacters() throws {
        let store = AgentSessionTokenStore(directoryURL: temporaryDirectory)
        let pid = Int32(ProcessInfo.processInfo.processIdentifier)

        try store.begin(kind: .codex, token: "../codex token", pid: pid)

        let session = try XCTUnwrap(store.activeSessions().first)
        XCTAssertEqual(session.id, "codex_token")
        XCTAssertEqual(session.kind, .codex)
    }
}
