#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ID="toolbar-edge-$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$ROOT/docs/testing/results/$RUN_ID"
STORAGE_DIR="/tmp/quitenote-$RUN_ID"
CASES_FILE="$ROOT/tools/toolbar-smoke/cases.json"
BINARY="$ROOT/.build/out/Products/Debug/QuiteNote"

mkdir -p "$EVIDENCE_DIR" "$STORAGE_DIR"

# Build first so the runner always matches the current working tree.
cd "$ROOT"
swift build

QN_TEST_STORAGE_ROOT="$STORAGE_DIR" \
QN_UI_EVIDENCE_DIR="$EVIDENCE_DIR" \
QN_TOOLBAR_SMOKE_CASES="$CASES_FILE" \
"$BINARY" --ui-smoke-run "$RUN_ID" >"$EVIDENCE_DIR/run.log" 2>&1 &
PID=$!

for _ in {1..40}; do
  COUNT=$(find "$EVIDENCE_DIR" -maxdepth 1 -name 'toolbar-*.png' | wc -l | tr -d ' ')
  [ "$COUNT" -ge 4 ] && break
  if ! kill -0 "$PID" 2>/dev/null; then break; fi
  sleep 0.5
done

sleep 1
kill "$PID" 2>/dev/null || true
sleep 1

COUNT=$(find "$EVIDENCE_DIR" -maxdepth 1 -name 'toolbar-*.png' | wc -l | tr -d ' ')
if [ "$COUNT" -ne 4 ]; then
  echo "FAIL: expected 4 PNG files, found $COUNT" >&2
  tail -80 "$EVIDENCE_DIR/run.log" >&2 || true
  exit 1
fi

echo "PASS: $RUN_ID"
echo "$EVIDENCE_DIR"
