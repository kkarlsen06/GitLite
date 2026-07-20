import AppKit
import CryptoKit
import Foundation
import SwiftUI
import XCTest
@testable import Kvist

final class CodiconTests: XCTestCase {
    private let officialSHA256: [Codicon: String] = [
        .gitBranch: "b88a5afd13aaab0c1d58d90cae19b8e7751856e54cc9d0c806d2aceba08802ad",
        .target: "cb12db5d9c9dfe8021eb03e344ca907399f44f8b970a67ea3dfdd862bb7b3717",
        .repoFetch: "b59f7fbb5255c7b4645bc23c5bd4261f38f0adbca913aa23c6c8075cc4cb80a4",
        .repoPull: "73bf9b5bb3dcff6fda97f2f1ebfc101994f828cd3a419b9ab1536760f72c31ff",
        .repoPush: "46dc9358c549d6264fade7ac9a9f8ef0bbbb21cdf037dff4e1ea8b3eae2c9f35",
        .sync: "3423d94a76e84061f67cc6172692bd5cc330a13985a2090c25669659918f583e",
        .check: "58e1762d74142ee78ee2422ae46498c1059e4f4812f9c7514e422a1f8d80235d"
    ]

    func testEveryVendoredCodiconLoadsAsAnImage() {
        for icon in Codicon.allCases {
            XCTAssertNotNil(
                NSImage(data: Data(icon.svg.utf8)),
                "Failed to load \(icon.rawValue)"
            )
        }
    }

    func testVendoredCodiconsMatchOfficialSVGsExactly() {
        for icon in Codicon.allCases {
            let digest = SHA256.hash(data: Data(icon.svg.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, officialSHA256[icon], "Modified \(icon.rawValue)")
        }
    }

    func testForcePushSystemSymbolIsAvailable() {
        XCTAssertNotNil(
            NSImage(systemSymbolName: "cloud.bolt", accessibilityDescription: nil)
        )
    }

    @MainActor
    func testBranchGlyphUsesProvidedColor() throws {
        let renderer = ImageRenderer(content: BranchGlyph(size: 16, color: .red))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let representation = try XCTUnwrap(
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        )

        let visibleColors = (0 ..< representation.pixelsHigh).flatMap { y in
            (0 ..< representation.pixelsWide).compactMap { x in
                representation.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            }
        }.filter { $0.alphaComponent > 0.25 }

        XCTAssertFalse(visibleColors.isEmpty)
        let containsRed = visibleColors.contains {
            $0.redComponent > $0.greenComponent + 0.4
                && $0.redComponent > $0.blueComponent + 0.4
        }
        XCTAssertTrue(containsRed)
        XCTAssertFalse(visibleColors.contains {
            $0.redComponent < 0.1
                && $0.greenComponent < 0.1
                && $0.blueComponent < 0.1
        })
    }

    @MainActor
    func testRepositoryLocationCustomSymbolLoads() {
        XCTAssertNotNil(RepositoryLocationSymbol.image)
        XCTAssertEqual(RepositoryLocationSymbol.image?.isTemplate, true)
    }
}
