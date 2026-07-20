import Foundation

enum PrivacyPreferences {
    // Preserve existing Codex consent while keeping consent provider-specific.
    static let codexProcessingConsentKey = "codexDataProcessingConsentV1"
    static let claudeProcessingConsentKey = "claudeDataProcessingConsentV1"

    static func processingConsentKey(for provider: AICommitMessageProvider) -> String {
        switch provider {
        case .codex: codexProcessingConsentKey
        case .claude: claudeProcessingConsentKey
        }
    }
}
