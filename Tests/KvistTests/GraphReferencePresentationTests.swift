import XCTest
@testable import Kvist

final class GraphReferencePresentationTests: XCTestCase {
    func testCurrentBranchUpstreamAppearsBeforeUnrelatedLocalBranches() {
        let references = [
            reference(
                id: "refs/heads/fix/domain",
                name: "fix/domain",
                kind: .localBranch
            ),
            reference(
                id: "refs/remotes/origin/main",
                name: "origin/main",
                kind: .remoteBranch
            ),
            reference(
                id: "refs/heads/main",
                name: "main",
                kind: .localBranch,
                isHead: true
            ),
            reference(
                id: "refs/tags/v1.0",
                name: "v1.0",
                kind: .tag
            )
        ]

        let displayed = GraphReferencePresentation.displayReferences(
            references,
            upstreamReferenceID: "refs/remotes/origin/main"
        )

        XCTAssertEqual(
            Array(displayed.prefix(2).map(\.name)),
            ["main", "origin/main"]
        )
    }

    func testRemainingReferencesHaveDeterministicKindAndNameOrder() {
        let references = [
            reference(id: "refs/tags/v2", name: "v2", kind: .tag),
            reference(id: "refs/heads/zeta", name: "zeta", kind: .localBranch),
            reference(
                id: "refs/remotes/origin/HEAD",
                name: "origin/HEAD",
                kind: .remoteBranch
            ),
            reference(
                id: "refs/remotes/upstream/main",
                name: "upstream/main",
                kind: .remoteBranch
            ),
            reference(id: "refs/heads/alpha", name: "alpha", kind: .localBranch)
        ]

        let displayed = GraphReferencePresentation.displayReferences(
            references,
            upstreamReferenceID: nil
        )

        XCTAssertEqual(
            displayed.map(\.name),
            ["alpha", "zeta", "upstream/main", "v2"]
        )
    }

    private func reference(
        id: String,
        name: String,
        kind: GitReferenceKind,
        isHead: Bool = false
    ) -> GitReference {
        GitReference(id: id, name: name, kind: kind, isHead: isHead)
    }
}
