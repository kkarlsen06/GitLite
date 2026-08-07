import XCTest
@testable import Kvist

final class TerminalPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.kvist.tests.terminal-preferences"

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testSelectedBundleIdentifierFallsBackToTerminal() {
        XCTAssertEqual(
            TerminalPreferences.selectedBundleIdentifier(defaults: defaults),
            TerminalPreferences.defaultBundleIdentifier
        )

        defaults.set("   ", forKey: TerminalPreferences.bundleIdentifierKey)
        XCTAssertEqual(
            TerminalPreferences.selectedBundleIdentifier(defaults: defaults),
            TerminalPreferences.defaultBundleIdentifier
        )
    }

    func testSelectedBundleIdentifierUsesStoredValue() {
        defaults.set("com.mitchellh.ghostty", forKey: TerminalPreferences.bundleIdentifierKey)
        XCTAssertEqual(
            TerminalPreferences.selectedBundleIdentifier(defaults: defaults),
            "com.mitchellh.ghostty"
        )
    }

    @MainActor
    func testAvailableApplicationsIncludesInstalledTerminal() {
        let applications = TerminalPreferences.availableApplications(
            selectedBundleIdentifier: TerminalPreferences.defaultBundleIdentifier
        )
        let terminal = applications.first {
            $0.bundleIdentifier == TerminalPreferences.defaultBundleIdentifier
        }

        XCTAssertNotNil(terminal)
        XCTAssertEqual(terminal?.isInstalled, true)
        XCTAssertEqual(terminal?.menuTitle, terminal?.name)
        XCTAssertFalse(terminal?.name.hasSuffix(".app") ?? true)
        XCTAssertTrue(applications.allSatisfy(\.isInstalled))
    }

    @MainActor
    func testAvailableApplicationsKeepsUninstalledSelection() {
        let missingIdentifier = "com.example.kvist-missing-terminal"
        let applications = TerminalPreferences.availableApplications(
            selectedBundleIdentifier: missingIdentifier
        )
        let selection = applications.first { $0.bundleIdentifier == missingIdentifier }

        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.isInstalled, false)
        XCTAssertEqual(selection?.menuTitle, "\(missingIdentifier) (not installed)")
        XCTAssertEqual(applications.filter { $0.bundleIdentifier == missingIdentifier }.count, 1)
    }

    @MainActor
    func testAvailableApplicationsDoesNotDuplicateSuggestedSelection() {
        let applications = TerminalPreferences.availableApplications(
            selectedBundleIdentifier: TerminalPreferences.defaultBundleIdentifier
        )
        let identifiers = applications.map(\.bundleIdentifier)

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testShellScriptRunnerKeepsTerminalsThatExecuteCommandFiles() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let handler = URL(fileURLWithPath: "/Applications/Fallback.app")

        for identifier in ["com.apple.Terminal", "com.googlecode.iterm2"] {
            XCTAssertTrue(TerminalPreferences.runsShellScripts(identifier))
            XCTAssertEqual(
                TerminalPreferences.shellScriptApplicationURL(
                    bundleIdentifier: identifier,
                    applicationURL: terminal,
                    defaultHandlerURL: handler
                ),
                terminal
            )
        }
    }

    func testShellScriptRunnerFallsBackForTerminalsThatDropCommandFiles() {
        let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app")
        let handler = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

        XCTAssertFalse(TerminalPreferences.runsShellScripts("com.mitchellh.ghostty"))
        XCTAssertEqual(
            TerminalPreferences.shellScriptApplicationURL(
                bundleIdentifier: "com.mitchellh.ghostty",
                applicationURL: ghostty,
                defaultHandlerURL: handler
            ),
            handler
        )
        XCTAssertEqual(
            TerminalPreferences.shellScriptApplicationURL(
                bundleIdentifier: "com.mitchellh.ghostty",
                applicationURL: ghostty,
                defaultHandlerURL: nil
            ),
            ghostty
        )
    }

    func testUninstalledTerminalErrorNamesTheApplication() {
        let error = RepositoryTerminalError.terminalNotFound(name: "Ghostty")
        XCTAssertEqual(
            error.errorDescription,
            "Ghostty could not be found. Choose another terminal app in Settings."
        )
    }

    @MainActor
    func testOpenThrowsWhenSelectedTerminalIsMissing() {
        XCTAssertThrowsError(
            try RepositoryTerminalLauncher.open(
                repositoryURL: FileManager.default.temporaryDirectory,
                sshRepository: nil,
                bundleIdentifier: "com.example.kvist-missing-terminal"
            )
        ) { error in
            XCTAssertEqual(
                (error as? RepositoryTerminalError)?.errorDescription,
                "com.example.kvist-missing-terminal could not be found. Choose another terminal app in Settings."
            )
        }
    }
}
