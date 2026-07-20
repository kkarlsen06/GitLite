# Kvist

Kvist is a compact native macOS client for Git® repositories.

## Included

- Open, clone, or initialize a Git repository, reopen it from the recents list, or drop a folder on the welcome screen
- Keep multiple repositories open in compact title-bar tabs (`⌘T` / `⌘W`, cycle with `⇧⌘[` / `⇧⌘]`)
- Recover open tabs, the selected workspace, expanded folders, commit text, and unsaved editor drafts after reopening Kvist
- Switch between Git and Files modes
- Edit text files in a native source editor with `⌘S` saving, and preview other file types with macOS Quick Look
- Create, rename, delete, and check out local or remote-tracking branches
- View staged, modified, deleted, renamed, and untracked files
- Stage or unstage one file or all files, stash changes, or discard all changes with confirmation
- Inspect working-tree and staged diffs
- Commit with `⌘Return`
- Refresh automatically when the worktree, index, refs, or HEAD changes
- Resize the graph vertically and the Git/diff split horizontally with their dividers
- Expand commits inline to inspect their changed files
- Open working-tree and historical diffs in a temporary editor-style side panel (`⎋` closes it)
- Use focused graph actions for integration, cherry-pick, revert, reset, tags, and recovery
- Generate a structured commit subject with Codex or Claude, choose the model and Codex reasoning effort, and inspect or customize the exact CLI command
- Fetch, pull using Git's configured strategy, push, or sync with rebase
- Browse a parent-based, vector-rendered Git history graph
- Include reflog-reachable commits in the graph for recovery
- Manage remotes, upstream branches, remote tags, and paused Git operations
- Keep scrolling to load older commits automatically
- Inspect commit metadata and changed-file statistics
- Open Preferences from the app menu, use the default Ayu Dark theme and Material icons, or import licensed editor themes from Eclipse Open VSX

Before downloading an Open VSX result, Kvist verifies that it is categorized as a theme, is downloadable, and declares a license. Imported themes remain subject to their publisher's license.

Kvist uses SwiftUI and the system `git` command. It does not embed Chromium, Electron, or an editor.

## Performance model

- Only the selected restored tab opens its repository and runs a filesystem watcher; inactive tabs load on first selection and suspend monitoring when hidden.
- Filesystem bursts are coalesced and bounded. Ordinary worktree edits run one lightweight status refresh, while Git metadata changes refresh history and references.
- A full repository snapshot combines branch, tracking, HEAD, and worktree state into one Git status process.
- Directory enumeration is serialized off the main thread, unchanged status results do not rebuild the file tree, and large files are stopped before expensive editor or Quick Look rendering.
- Editor and commit-message keystrokes are isolated from repository chrome; diff rendering and line-number lookup are lazy/incremental so typing and scrolling do not repeatedly parse whole documents.

## Build

```sh
chmod +x Scripts/package.sh
Scripts/package.sh
open dist/Kvist.app
```

Requires macOS 26 or later and the Apple command-line developer tools.

For a notarized direct-download release, configure a Developer ID identity and
notary profile, then run `Scripts/release.sh`. See [DISTRIBUTION.md](DISTRIBUTION.md).

Run the release performance suite with `Scripts/benchmark.sh`. It benchmarks
GitLite, Paeonia, and Tidex and fails when a committed guardrail regresses. See
[PERFORMANCE.md](PERFORMANCE.md) for the methodology and result format. Use
`Scripts/benchmark-tabs.sh` for the isolated 20-temporary-repository tab-scaling
workload.

Commit-message generation uses the Codex or Claude CLI already installed and
authenticated on the Mac. Codex can also use the binary bundled with the ChatGPT
app. Install and sign in to the selected provider's CLI before generating a
message. Preferences loads Codex's current model catalog and supported reasoning
efforts from the CLI; Claude's
stable aliases are shown because Claude Code does not expose a model-list command.
Exact model IDs remain editable for both providers.
If an agent returns an invalid response, Kvist keeps the raw output available
through the error dialog's copyable details view.

## Legal

Kvist is available under the MIT License. See [LICENSE](LICENSE),
[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES), and [PRIVACY.md](PRIVACY.md).

Git and the Git logo are either registered trademarks or trademarks of Software
Freedom Conservancy, Inc., corporate home of the Git Project, in the United
States and/or other countries. Kvist is an independent project and is not
affiliated with or endorsed by the Git Project or Software Freedom Conservancy.
