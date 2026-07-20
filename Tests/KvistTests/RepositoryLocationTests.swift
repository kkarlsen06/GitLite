import AppKit
import XCTest
@testable import Kvist

final class RepositoryLocationTests: XCTestCase {
    @MainActor
    func testCopyDirectoryPathWritesStandardizedRepositoryPath() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("RepositoryLocationTests.\(UUID().uuidString)")
        )
        let repositoryURL = URL(fileURLWithPath: "/tmp/project/../repository")

        RepositoryLocationActions.copyDirectoryPath(
            repositoryURL,
            to: pasteboard
        )

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "/tmp/repository"
        )
    }
}
