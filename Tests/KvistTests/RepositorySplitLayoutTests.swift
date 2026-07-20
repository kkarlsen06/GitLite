import XCTest
@testable import Kvist

final class RepositorySplitLayoutTests: XCTestCase {
    func testDefaultSplitDividesAvailableWidthEqually() {
        let metrics = RepositorySplitLayout.metrics(
            totalWidth: 931,
            preferredFraction: RepositorySplitLayout.defaultFraction
        )

        XCTAssertEqual(metrics.repositoryWidth, 465)
        XCTAssertEqual(metrics.detailWidth, 465)
    }

    func testSplitPreservesPreferredProportionAsWindowResizes() {
        let compact = RepositorySplitLayout.metrics(
            totalWidth: 1_001,
            preferredFraction: 0.4
        )
        let wide = RepositorySplitLayout.metrics(
            totalWidth: 1_501,
            preferredFraction: 0.4
        )

        XCTAssertEqual(compact.repositoryWidth, 400)
        XCTAssertEqual(compact.detailWidth, 600)
        XCTAssertEqual(wide.repositoryWidth, 600)
        XCTAssertEqual(wide.detailWidth, 900)
    }

    func testSplitClampsBothPanelsToMinimumWidth() {
        let leading = RepositorySplitLayout.metrics(
            totalWidth: 1_001,
            preferredFraction: 0.1
        )
        let trailing = RepositorySplitLayout.metrics(
            totalWidth: 1_001,
            preferredFraction: 0.9
        )

        XCTAssertEqual(leading.repositoryWidth, 300)
        XCTAssertEqual(leading.detailWidth, 700)
        XCTAssertEqual(trailing.repositoryWidth, 700)
        XCTAssertEqual(trailing.detailWidth, 300)
    }

    func testNarrowWindowKeepsBothPanelsVisible() {
        let metrics = RepositorySplitLayout.metrics(
            totalWidth: 401,
            preferredFraction: 0.8
        )

        XCTAssertEqual(metrics.repositoryWidth, 200)
        XCTAssertEqual(metrics.detailWidth, 200)
        XCTAssertEqual(metrics.allowedRepositoryWidths, 200...200)
    }

    func testInvalidStoredFractionFallsBackToDefault() {
        let metrics = RepositorySplitLayout.metrics(
            totalWidth: 931,
            preferredFraction: .nan
        )

        XCTAssertEqual(metrics.repositoryWidth, 465)
        XCTAssertEqual(metrics.detailWidth, 465)
    }

    func testConflictMinimumPreservesTheExistingExpandedWidthContract() {
        let metrics = RepositorySplitLayout.metrics(
            totalWidth: RepositorySplitLayout.conflictExpandedWidth,
            preferredFraction: RepositorySplitLayout.defaultFraction,
            minimumDetailWidth: RepositorySplitLayout.conflictDiffWidth
        )

        XCTAssertEqual(metrics.repositoryWidth, 465)
        XCTAssertEqual(metrics.detailWidth, 560)
        XCTAssertEqual(
            RepositorySplitLayout.conflictExpandedWidth,
            1_026
        )
    }
}
