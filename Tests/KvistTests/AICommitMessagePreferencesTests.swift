import Foundation
import XCTest
@testable import Kvist

final class AICommitMessagePreferencesTests: XCTestCase {
    func testConfigurationKeepsProviderSpecificModelsAndCommands() throws {
        let suiteName = "AICommitMessagePreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            AICommitMessageProvider.claude.rawValue,
            forKey: AICommitMessagePreferences.providerKey
        )
        defaults.set("claude-opus-4-6", forKey: AICommitMessagePreferences.claudeModelKey)
        defaults.set("custom {model}", forKey: AICommitMessagePreferences.claudeCommandTemplateKey)
        defaults.set("gpt-custom", forKey: AICommitMessagePreferences.codexModelKey)

        let configuration = AICommitMessageConfiguration.load(defaults: defaults)

        XCTAssertEqual(configuration.provider, .claude)
        XCTAssertEqual(configuration.model, "claude-opus-4-6")
        XCTAssertNil(configuration.reasoningEffort)
        XCTAssertEqual(configuration.commandTemplate, "custom {model}")
    }

    func testCodexConfigurationLoadsReasoningEffortAndMigratesLegacyDefault() throws {
        let suiteName = "AICommitMessagePreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            AICommitMessageProvider.codex.rawValue,
            forKey: AICommitMessagePreferences.providerKey
        )
        defaults.set(
            AICommitMessageReasoningEffort.max.rawValue,
            forKey: AICommitMessagePreferences.codexReasoningEffortKey
        )
        defaults.set(
            AICommitMessageProvider.codex.legacyDefaultCommandTemplate,
            forKey: AICommitMessagePreferences.codexCommandTemplateKey
        )

        let configuration = AICommitMessageConfiguration.load(defaults: defaults)

        XCTAssertEqual(configuration.reasoningEffort, .max)
        XCTAssertEqual(
            configuration.commandTemplate,
            AICommitMessageProvider.codex.defaultCommandTemplate
        )
    }

    func testCodexModelCatalogUsesVisibleModelsInPriorityOrder() throws {
        let output = """
        warning: cached catalog
        {"models":[
          {"slug":"hidden","display_name":"Hidden","visibility":"hide","priority":0},
          {"slug":"fast","display_name":"Fast","visibility":"list","priority":2},
          {"slug":"best","display_name":"Best","visibility":"list","priority":1,"default_reasoning_level":"medium","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"}]}
        ]}
        """

        XCTAssertEqual(
            try AICommitMessageModelCatalog.parseCodexModels(output),
            [
                AICommitMessageModel(
                    id: "best",
                    name: "Best",
                    supportedReasoningEfforts: [.low, .medium, .high],
                    defaultReasoningEffort: .medium
                ),
                AICommitMessageModel(id: "fast", name: "Fast")
            ]
        )
    }

    func testCommandTemplateShellQuotesUserControlledValues() throws {
        let command = try AICommitMessageGenerator.expandCommandTemplate(
            "{executable} --model {model} --effort {reasoning-effort} --cd {repository}",
            executableURL: URL(fileURLWithPath: "/tmp/agent"),
            model: "model'; touch /tmp/should-not-run; '",
            reasoningEffort: .xhigh,
            repositoryURL: URL(fileURLWithPath: "/tmp/repo name"),
            schemaURL: URL(fileURLWithPath: "/tmp/schema"),
            outputURL: URL(fileURLWithPath: "/tmp/output")
        )

        XCTAssertEqual(
            command,
            "'/tmp/agent' --model 'model'\"'\"'; touch /tmp/should-not-run; '\"'\"'' --effort 'xhigh' --cd '/tmp/repo name'"
        )
    }
}
