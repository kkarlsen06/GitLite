#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Kvist.app"
TIMESTAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
OUTPUT="${KVIST_PERFORMANCE_OUTPUT:-$ROOT/Benchmarks/Results/$TIMESTAMP}"
GITLITE="${KVIST_PERFORMANCE_GITLITE_REPOSITORY:-$ROOT}"
PAEONIA="${KVIST_PERFORMANCE_PAEONIA_REPOSITORY:-$ROOT/../paeonia}"
TIDEX="${KVIST_PERFORMANCE_TIDEX_REPOSITORY:-$ROOT/../tidex}"

for repository in "$GITLITE" "$PAEONIA" "$TIDEX"; do
  if ! git -C "$repository" rev-parse --git-dir >/dev/null 2>&1; then
    print -u2 "error: benchmark repository is unavailable: $repository"
    print -u2 "Set the matching KVIST_PERFORMANCE_*_REPOSITORY variable and retry."
    exit 1
  fi
done

"$ROOT/Scripts/package.sh" "$APP"

BIN_DIR="$(swift build \
  --package-path "$ROOT" \
  --scratch-path "$ROOT/.build" \
  -c release \
  --show-bin-path)"

"$BIN_DIR/KvistBenchmark" \
  --app "$APP" \
  --output "$OUTPUT" \
  --repository "GitLite=$GITLITE" \
  --repository "Paeonia=$PAEONIA" \
  --repository "Tidex=$TIDEX" \
  --launch-samples 20 \
  --git-samples 30 \
  --external-refresh-samples 30 \
  --event-storm-trials 10 \
  --idle-samples 5 \
  --idle-duration 10 \
  --settle-duration 5

print "$OUTPUT"
