import Foundation
import XCTest
@testable import Kvist

final class RepositoryViewerSizingTests: XCTestCase {
    func testSavedViewerWidthIsSharedAcrossSizingInstances() throws {
        let suiteName = "RepositoryViewerSizingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RepositoryViewerSizing(defaults: defaults)
            .saveExpandedContentWidth(1_180)

        XCTAssertEqual(
            RepositoryViewerSizing(defaults: defaults).savedExpandedContentWidth,
            1_180
        )
    }

    func testSavedViewerWidthOverridesDefaultForLaterOpenings() throws {
        let suiteName = "RepositoryViewerSizingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sizing = RepositoryViewerSizing(defaults: defaults)
        sizing.saveExpandedContentWidth(1_180)

        XCTAssertEqual(
            sizing.targetContentWidth(
                currentContentWidth: 465,
                defaultExpandedContentWidth: 931,
                minimumExpandedContentWidth: nil
            ),
            1_180
        )
    }

    func testConflictMinimumTemporarilyOverridesSavedViewerWidth() throws {
        let suiteName = "RepositoryViewerSizingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sizing = RepositoryViewerSizing(defaults: defaults)
        sizing.saveExpandedContentWidth(800)

        XCTAssertEqual(
            sizing.targetContentWidth(
                currentContentWidth: 465,
                defaultExpandedContentWidth: 931,
                minimumExpandedContentWidth: 1_026
            ),
            1_026
        )
        XCTAssertEqual(sizing.savedExpandedContentWidth, 800)
    }

    func testOnlyManualResizeIsEligibleForPersistence() {
        XCTAssertNil(
            RepositoryViewerSizing.manuallyResizedWidth(
                currentContentWidth: 931,
                automaticContentWidth: 931
            )
        )
        XCTAssertEqual(
            RepositoryViewerSizing.manuallyResizedWidth(
                currentContentWidth: 1_120,
                automaticContentWidth: 931
            ),
            1_120
        )
    }

    func testSavedViewerWidthAndSplitFractionRemainIndependent() throws {
        let suiteName = "RepositoryViewerSizingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sizing = RepositoryViewerSizing(defaults: defaults)
        sizing.saveExpandedContentWidth(1_180)

        let expandedWidth = sizing.targetContentWidth(
            currentContentWidth: 465,
            defaultExpandedContentWidth: RepositorySplitLayout.expandedWidth,
            minimumExpandedContentWidth: nil
        )
        let split = RepositorySplitLayout.metrics(
            totalWidth: expandedWidth,
            preferredFraction: 0.4
        )

        XCTAssertEqual(expandedWidth, 1_180)
        XCTAssertEqual(
            split.repositoryWidth + RepositorySplitLayout.separatorWidth
                + split.detailWidth,
            expandedWidth
        )
        XCTAssertEqual(
            split.repositoryWidth / split.availablePaneWidth,
            0.4,
            accuracy: 0.000_1
        )
    }
}
