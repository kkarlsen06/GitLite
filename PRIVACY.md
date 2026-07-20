# Kvist Privacy Notice

Effective: July 21, 2026

Kvist does not include advertising, analytics, telemetry, or a developer-
operated account service. Repository browsing, editing, Git commands, settings,
and workspace restoration are handled locally on the Mac.

## AI commit-message generation

Kvist only invokes the selected AI agent after the user presses the commit-
message generation button and accepts the provider-specific in-app disclosure.
Kvist launches a Codex or Claude command-line tool already installed and
authenticated by the user. The selected agent is instructed to read the staged
Git diff and may transmit that diff, the repository path, and any commit-message
instructions to OpenAI or Anthropic using the user's account.

Kvist does not receive a separate copy of that data. It stores the returned
commit subject locally in the repository workspace state. Use this feature only
when authorized to send the staged source code to the service configured in the
selected command-line tool. The selected provider's terms and privacy policy
govern its processing.

The provider, model identifier, Codex reasoning effort, and complete command
template are visible in Kvist Preferences. Advanced users may edit the command. Kvist expands the
documented placeholders, sends the generation prompt over standard input, and
runs the result through `/bin/zsh -lc` with the user's permissions. A custom
command may process or transmit data beyond Kvist's default behavior.

Consent is stored separately for Codex and Claude and can be withdrawn in Kvist
Preferences. The next attempt with that provider will show the disclosure again.

## Theme discovery

When the user searches for or imports a theme, Kvist connects directly to
the Eclipse Open VSX registry. Open VSX receives normal network information and
the search query. Imported themes remain subject to their publisher's license
and the Open VSX terms and privacy practices.

## Support

Questions about this notice can be opened as an issue in the Kvist source
repository. Do not include confidential repository contents in a public issue.
