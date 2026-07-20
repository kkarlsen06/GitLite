# Kvist release performance benchmarks

Kvist ships a release-only benchmark harness that exercises the packaged app
and the same `GitClient` paths used by the UI. The command builds the complete
release product; it does not compile out features, change file limits, or add a
runtime dependency.

## Run the benchmark

Quit any existing Kvist process, connect the Mac to power, close unrelated
high-load applications, and leave each repository in a stable working-tree
state. Then run:

```sh
Scripts/benchmark.sh
```

For the isolated 20-tab workload only, run:

```sh
Scripts/benchmark-tabs.sh
```

For the supported file and diff limits, run:

```sh
Scripts/benchmark-interactions.sh
```

For large and highly connected histories, run:

```sh
Scripts/benchmark-history.sh
```

The history command creates its repository below a unique temporary directory
and streams a deterministic `git fast-import` fixture with 20,001 commits,
1,000 merges, 501 branches, 500 tags, and a head commit that changes exactly
1,000 files. It never opens or modifies an existing repository, and removes
the fixture after the run. Set `KVIST_HISTORY_PERFORMANCE_OUTPUT` to choose its
result directory.

The interaction command creates a committed temporary repository containing an
exactly 1 MiB source file, an exactly 20,000-line source file, an exactly
20,000-character line, and an unstaged diff with exactly 10,000 changed lines.
It launches the packaged release app and exercises the production source and
diff views. Set `KVIST_INTERACTION_PERFORMANCE_OUTPUT` to choose its result
directory.

Both commands create 20 unique committed repositories below a temporary run
directory. They are removed after the run. External-edit measurements use a
temporary copy of each supplied repository, so benchmark writes never modify a
user repository.

The defaults are:

- GitLite: this repository (the upstream repository retains that name)
- Paeonia: `../paeonia`
- Tidex: `../tidex`

Override a location when needed:

```sh
KVIST_PERFORMANCE_GITLITE_REPOSITORY=/absolute/path/GitLite \
KVIST_PERFORMANCE_PAEONIA_REPOSITORY=/absolute/path/paeonia \
KVIST_PERFORMANCE_TIDEX_REPOSITORY=/absolute/path/tidex \
Scripts/benchmark.sh
```

Set `KVIST_PERFORMANCE_OUTPUT` to choose the result directory. Otherwise the
command creates a UTC-dated directory below `Benchmarks/Results/`. A complete
run takes several minutes and intentionally refuses fewer than 20 launch
samples, 30 samples of each Git operation, 30 external-edit refreshes, 10
100-file event storms per repository, 5 idle samples, or idle intervals shorter
than 10 seconds.

`Benchmarks/Results/` contains local generated runs and is ignored by Git. Move
reviewed reference runs to `Benchmarks/Baselines/` when they should be retained
for future regression comparisons.

The command exits nonzero if a measurement fails or a guardrail regresses. It
always writes these reviewable artifacts after a completed measurement run:

- `raw-results.json`: metadata, configuration, every raw sample, and every
  guardrail decision
- `report.md`: median and nearest-rank p95 summaries, guardrail results, and the
  raw samples in a human-readable report

Keep the machine, checkout state, power mode, and OS version consistent when
comparing runs. The harness warms the Git paths once before recording and does
not purge normal macOS filesystem caches.

## Measurement definitions

- **Launch to initial frame** starts immediately before `Process.run()` starts
  the packaged release executable and ends after Kvist creates its window,
  forces the initial display pass, and flushes the Core Animation transaction.
- **Startup peak physical footprint** is macOS
  `ri_lifetime_max_phys_footprint` after the initial repository is ready. It is
  collected for every launch sample.
- **Settled physical footprint** is macOS `ri_phys_footprint` after initial
  repository loading plus a five-second settling interval.
- **Idle CPU** is the process user-plus-system CPU-time delta divided by the
  wall-clock duration of each 10-second idle interval.
- **Idle wakeups/second** is the delta of package-idle plus interrupt wakeups
  from `proc_pid_rusage`, divided by the measured idle interval.
- **Working-tree refresh** calls `GitClient.workingTreeSnapshot()`, the same
  status-only path used for ordinary filesystem changes.
- **External edit to publication** starts immediately before writing an
  untracked file outside `RepositoryModel` and ends when the model publishes
  that file in its working-tree changes.
- **Event storm settle** starts before creating 100 files inside a new
  untracked directory, requires those writes to finish within 100 ms, and ends
  when `RepositoryModel` publishes the collapsed directory change. Refresh
  counters verify one working-tree snapshot and zero full snapshots per burst.
- **Initial repository loading** includes root discovery, the initial
  `GitClient.snapshot()` (status, references, and history), and watcher-path
  discovery.
- **Unopened-tab switch** starts before selecting one of the 19 inactive lazy
  tabs and ends after its repository is loaded and the window has rendered.
- **Loaded-tab switch** selects and explicitly renders an already loaded tab.
- **Rapid tab cycling** makes 100 complete passes over all 20 tabs, returning to
  the original tab. Every selection yields through the next main-queue turn.
- **Main-thread stall** is the longest continuous main-thread operation among
  all 2,000 rapid selections and the 100 explicit loaded-tab renders. Dispatch
  gaps while macOS does not schedule the benchmark process are excluded.
- **Unopened-tab footprint delta** compares a settled process with 20 restored
  tabs (only the selected repository loaded) against a settled single-tab
  process using the same temporary fixture.
- **Retained tab-state footprint delta** is measured after all 20 repositories
  have been visited. **Rapid-cycle footprint delta** compares settled physical
  footprint immediately before cycling with the settled footprint after
  returning to the original tab.
- **App bundle size** is the sum of logical bytes for every regular file in the
  packaged `.app`.
- **Compressed app size** is the byte size of a `ditto -c -k --keepParent` ZIP
  of that same package.
- **Maximum source open** starts before the repository model requests the
  exactly 1 MiB file and ends after the source view has installed and displayed
  it. Thirty recorded opens alternate with the 20,000-character fixture so
  every sample replaces real editor content.
- **Large diff open** includes the production Git diff and preview paths,
  attributed diff construction, layout, and the first displayed frame. Thirty
  recorded opens alternate with source content.
- **Typing input to display** records each of 1,000 consecutive AppKit text
  insertions through the production binding and an explicit window display
  pass. The editor is focused and settled before the first sample.
- **Continuous scrolling** uses a display link at the active screen cadence for
  ten seconds in each view. Missed display-link intervals are dropped frames;
  the longest display-link interval or scroll-and-display operation is the
  main-thread stall.
- **Near-end line jump** records thirty jumps to line 19,950 in the open
  20,000-line source fixture, including layout and display.
- **File/diff lifecycle footprint** compares physical footprint after a settled
  baseline with the settled footprint after 100 cycles. Each cycle opens and
  closes both the maximum source and large diff. The final state must have no
  new `Kvist-Git-Preview-*` directory and no outstanding repository task.
- **Initial history** measures thirty direct production queries for the first
  50 commits after one warmup query.
- **Repository open to rendered graph** measures twenty complete repository
  opens through the model, next main-run-loop publication, AppKit layout and
  display, and Core Animation flush.
- **History pagination** measures every appended 50-commit page while loading
  5,000 visible rows, including Git traversal, graph layout, model publication,
  table update, layout, and display. The 495 samples span five independent
  memory runs.
- **Graph scope switch** measures twenty alternating All and Current requests
  through query, publication, and display. Each publication is verified against
  its requested scope.
- **Reference parse and display** measures twenty parses and display passes for
  the fixture's 1,001 visible references.
- **History scrolling** drives the 5,000-row AppKit graph continuously for ten
  seconds using the active display cadence. Missed display-link intervals are
  dropped frames, and the longest interval or scroll-and-display operation is
  the main-thread stall.
- **5,000-row footprint** compares physical footprint after the initial 50 rows
  against the settled footprint after 5,000 visible rows, repeated five times.
- **History lifecycle** repeats 100 overlapping pagination, cancellation, and
  scope-switch cycles, returns to the initial All page, then checks graph task
  ownership, stale-publication counters, and settled physical footprint.
- **Large commit expansion** measures twenty expansions of the head commit's
  1,000 changed files through Git enumeration, model publication, table update,
  layout, and display.

Median is the middle value (or mean of the two middle values). p95 is the
nearest-rank 95th percentile: sorted sample at `ceil(0.95 × count)`.

## Enforced guardrails

| Metric | Guardrail |
| --- | ---: |
| App bundle | ≤ 2.75 MiB |
| Compressed app | ≤ 1.15 MiB |
| Launch | median ≤ 250 ms; p95 ≤ 275 ms |
| Startup peak physical footprint | every sample ≤ 35 MiB |
| Settled physical footprint | every sample ≤ 50 MiB |
| Idle CPU | every sample ≤ 0.01% |
| Idle wakeups | every sample ≤ 1.2/second |
| Working-tree refresh | median ≤ 35 ms; p95 ≤ 50 ms |
| Initial repository loading | median ≤ 90 ms; p95 ≤ 130 ms |
| External-edit latency | median ≤ 180 ms; p95 ≤ 200 ms |
| Event-storm latency | p95 ≤ 220 ms; writes ≤ 100 ms |
| Refresh fan-out | exactly 1 working-tree and 0 full snapshots per worktree-only burst |
| Restored tab fixtures | exactly 20; initially loaded repositories exactly 1 |
| Inactive tabs before selection | exactly 0 Git commands and 0 watchers |
| Application repository watchers | exactly 1 after quiescence and rapid cycling |
| Unopened-tab footprint delta | ≤ 10 MiB |
| Unopened-tab switch | median ≤ 200 ms; p95 ≤ 300 ms |
| Loaded-tab switch | median ≤ 30 ms; p95 ≤ 50 ms |
| Rapid cycling | exactly 100 passes; 0 orphan Git processes/tasks; footprint delta ≤ 3 MiB |
| Main-thread stall | maximum ≤ 50 ms |
| Retained tab-state footprint delta | ≤ 30 MiB |
| Tab workload idle use | CPU ≤ 0.01%; wakeups ≤ 1.2/second |

Artifact-size guardrails apply once to the release package. All runtime and Git
guardrails apply independently to GitLite, Paeonia, and Tidex so one small
repository cannot conceal a regression in another.

The original evaluator remains 56 guardrails (2 app-wide plus 18 for each of
the three representative repositories). The 20 tab-specific guardrails are
evaluated separately and appended to the same raw and Markdown reports.

The interaction evaluator adds 28 independent checks for exact fixtures,
sample counts, source/diff latency, typing latency and stalls, display-link
scrolling, line jumps, lifecycle footprint and cleanup, and the stricter release
artifact sizes. Its limits are:

| Interaction metric | Guardrail |
| --- | ---: |
| Maximum source open | median ≤ 100 ms; p95 ≤ 150 ms |
| Large diff open | median ≤ 125 ms; p95 ≤ 200 ms |
| 1,000 edits | median ≤ 8 ms; p95 ≤ 16 ms; maximum ≤ 33 ms |
| Editor and diff scrolling | 10 seconds each; dropped frames ≤ 1%; maximum stall ≤ 33 ms |
| Jump to line 19,950 | 30 samples; p95 ≤ 50 ms |
| 100 file/diff cycles | settled footprint delta ≤ 5 MiB; zero orphan previews/tasks |

The large-history evaluator adds 32 independent checks for fixture shape,
sample counts, latency, rendering cadence, memory, lifecycle correctness, and
release artifact size. Its limits are:

| Large-history metric | Guardrail |
| --- | ---: |
| Fixture | ≥20,000 commits; ≥1,000 merges; ≥500 branches; ≥500 tags; 1,000 expanded files |
| Initial 50 commits | 30 samples; median ≤75 ms; p95 ≤120 ms |
| Open to rendered graph | 20 samples; median ≤150 ms; p95 ≤220 ms |
| Append each 50-commit page | ≥30 samples; median ≤80 ms; p95 ≤130 ms |
| All/Current scope switch | 20 samples; p95 ≤150 ms |
| Parse/display ≥1,000 references | 20 samples; p95 ≤120 ms |
| Ten-second graph scroll | dropped frames ≤1%; maximum stall ≤25 ms |
| 5,000-row footprint | 5 samples; maximum delta ≤20 MiB |
| 100 pagination/cancellation/scope cycles | 0 orphan tasks; 0 stale publications; settled delta ≤3 MiB |
| Expand 1,000-file commit | 20 samples; p95 ≤175 ms; maximum stall ≤33 ms |
| Release artifacts | app ≤2.75 MiB; compressed app ≤1.15 MiB |
