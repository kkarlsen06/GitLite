#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Kvist.app"
TIMESTAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
OUTPUT="${KVIST_INTERACTION_PERFORMANCE_OUTPUT:-$ROOT/Benchmarks/Results/$TIMESTAMP-interactions}"

"$ROOT/Scripts/package.sh" "$APP"

BIN_DIR="$(swift build \
  --package-path "$ROOT" \
  --scratch-path "$ROOT/.build" \
  -c release \
  --show-bin-path)"

"$BIN_DIR/KvistInteractionBenchmark" \
  --app "$APP" \
  --output "$OUTPUT"

print "$OUTPUT"
