import Foundation

enum AICommitMessageReasoningEffort: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        case .max: "Maximum"
        case .ultra: "Ultra"
        }
    }
}

enum AICommitMessageProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var serviceName: String {
        switch self {
        case .codex: "OpenAI"
        case .claude: "Anthropic"
        }
    }

    var executableName: String { rawValue }

    var defaultModel: String {
        switch self {
        case .codex: "gpt-5.6-sol"
        case .claude: "sonnet"
        }
    }

    var suggestedModels: [AICommitMessageModel] {
        switch self {
        case .codex:
            [
                AICommitMessageModel(
                    id: "gpt-5.6-sol",
                    name: "GPT-5.6-Sol",
                    supportedReasoningEfforts: AICommitMessageReasoningEffort.allCases,
                    defaultReasoningEffort: .low
                ),
                AICommitMessageModel(
                    id: "gpt-5.6-terra",
                    name: "GPT-5.6-Terra",
                    supportedReasoningEfforts: AICommitMessageReasoningEffort.allCases,
                    defaultReasoningEffort: .medium
                )
            ]
        case .claude:
            [
                AICommitMessageModel(id: "sonnet", name: "Sonnet (latest)"),
                AICommitMessageModel(id: "opus", name: "Opus (latest)"),
                AICommitMessageModel(id: "haiku", name: "Haiku (latest)")
            ]
        }
    }

    var defaultCommandTemplate: String {
        switch self {
        case .codex:
            return "{executable} exec --model {model} --config model_reasoning_effort={reasoning-effort} --ephemeral --sandbox read-only --color never --cd {repository} --output-schema {schema} --output-last-message {output} -"
        case .claude:
            return "{executable} --print --model {model} --effort high --permission-mode plan --tools '' --no-session-persistence --output-format json --json-schema {schema-json}"
        }
    }

    var legacyDefaultCommandTemplate: String? {
        switch self {
        case .codex:
            "{executable} exec --model {model} --config 'model_reasoning_effort=\"xhigh\"' --ephemeral --sandbox read-only --color never --cd {repository} --output-schema {schema} --output-last-message {output} -"
        case .claude:
            nil
        }
    }

    var modelSourceDescription: String {
        switch self {
        case .codex:
            "Models reported by the installed Codex CLI"
        case .claude:
            "Aliases supported by Claude Code; exact model IDs are also accepted"
        }
    }
}

struct AICommitMessageModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let supportedReasoningEfforts: [AICommitMessageReasoningEffort]
    let defaultReasoningEffort: AICommitMessageReasoningEffort?

    init(
        id: String,
        name: String,
        supportedReasoningEfforts: [AICommitMessageReasoningEffort] = [],
        defaultReasoningEffort: AICommitMessageReasoningEffort? = nil
    ) {
        self.id = id
        self.name = name
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
    }
}

struct AICommitMessageConfiguration: Equatable, Sendable {
    let provider: AICommitMessageProvider
    let model: String
    let reasoningEffort: AICommitMessageReasoningEffort?
    let commandTemplate: String

    init(
        provider: AICommitMessageProvider,
        model: String,
        reasoningEffort: AICommitMessageReasoningEffort? = nil,
        commandTemplate: String
    ) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.commandTemplate = commandTemplate
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        let provider = AICommitMessageProvider(
            rawValue: defaults.string(forKey: AICommitMessagePreferences.providerKey) ?? ""
        ) ?? .codex
        let model = defaults.string(forKey: AICommitMessagePreferences.modelKey(for: provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let command = defaults.string(
            forKey: AICommitMessagePreferences.commandTemplateKey(for: provider)
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEffort = provider == .codex
            ? AICommitMessageReasoningEffort(
                rawValue: defaults.string(
                    forKey: AICommitMessagePreferences.codexReasoningEffortKey
                ) ?? ""
            ) ?? .xhigh
            : nil
        let storedCommand = command.flatMap { $0.isEmpty ? nil : $0 }
        let normalizedCommand = storedCommand == provider.legacyDefaultCommandTemplate
            ? provider.defaultCommandTemplate
            : storedCommand

        return Self(
            provider: provider,
            model: model.flatMap { $0.isEmpty ? nil : $0 } ?? provider.defaultModel,
            reasoningEffort: reasoningEffort,
            commandTemplate: normalizedCommand
                ?? provider.defaultCommandTemplate
        )
    }
}

enum AICommitMessagePreferences {
    static let providerKey = "aiCommitMessageProvider"
    static let codexModelKey = "aiCommitMessageCodexModel"
    static let claudeModelKey = "aiCommitMessageClaudeModel"
    static let codexReasoningEffortKey = "aiCommitMessageCodexReasoningEffort"
    static let codexCommandTemplateKey = "aiCommitMessageCodexCommandTemplate"
    static let claudeCommandTemplateKey = "aiCommitMessageClaudeCommandTemplate"

    static func modelKey(for provider: AICommitMessageProvider) -> String {
        switch provider {
        case .codex: codexModelKey
        case .claude: claudeModelKey
        }
    }

    static func commandTemplateKey(for provider: AICommitMessageProvider) -> String {
        switch provider {
        case .codex: codexCommandTemplateKey
        case .claude: claudeCommandTemplateKey
        }
    }
}
