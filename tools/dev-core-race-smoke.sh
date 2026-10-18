#!/bin/zsh
set -euo pipefail

ROOT="${1:-$(mktemp -d)}"
BINARY="${QN_DEV_CORE_BINARY:-$(cd "$(dirname "$0")/.." && pwd)/.build/debug/QuiteNoteCoreService}"
DATABASE="$ROOT/ClipboardHistory.sqlite"
[[ -x "$BINARY" ]] || { echo "Missing executable: $BINARY" >&2; exit 1; }
mkdir -p "$ROOT"

# Use a Swift helper to exercise the repository directly: two simultaneous
# processes each issue upserts for shared and unique payloads.
cat > "$ROOT/race.swift" <<'SWIFT'
import Foundation
import QuiteNoteSharedStorage

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let iterations = Int(arguments[2]),
      let processID = Int(arguments[3]) else {
    FileHandle.standardError.write("usage: race <database> <iterations> <process-id>\n".data(using: .utf8)!)
    exit(2)
}

let repository = ClipboardHistoryRepository(
    persistence: ClipboardHistoryPersistence(databaseURL: URL(fileURLWithPath: arguments[1]))
)
for index in 0..<iterations {
    do {
        _ = try repository.insertText("race-shared")
        _ = try repository.insertText("race-\(processID)-\(index)")
    } catch {
        FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
SWIFT

# SwiftPM does not emit a shared library, so link the helper with target objects.
OBJECTS=(
  .build/debug/QuiteNoteSharedStorage.build/ClipboardEntry.swift.o
  .build/debug/QuiteNoteSharedStorage.build/ClipboardHistoryPersistence.swift.o
  .build/debug/QuiteNoteSharedStorage.build/CoreClipboardStore.swift.o
  .build/debug/QuiteNoteSharedStorage.build/ClipboardHistoryRepository.swift.o
)
swiftc -I .build/debug/Modules "$ROOT/race.swift" "${OBJECTS[@]}" -framework CoreData -framework Foundation -o "$ROOT/race"

"$ROOT/race" "$DATABASE" 100 1 &
PID1=$!
"$ROOT/race" "$DATABASE" 100 2 &
PID2=$!
wait "$PID1"
wait "$PID2"

COUNT=$(sqlite3 "$DATABASE" "select count(*) from ZCDCLIPBOARDENTRY where ZPLAINTEXT like 'race-%';")
SHARED=$(sqlite3 "$DATABASE" "select count(*) from ZCDCLIPBOARDENTRY where ZPLAINTEXT='race-shared';")
UNIQUE=$(sqlite3 "$DATABASE" "select count(*) from ZCDCLIPBOARDENTRY where ZPLAINTEXT != 'race-shared' and ZPLAINTEXT like 'race-%';")

echo "database=$DATABASE"
echo "shared_rows=$SHARED"
echo "unique_rows=$UNIQUE"
echo "total_rows=$COUNT"
if [[ "$SHARED" == 1 && "$UNIQUE" == 200 && "$COUNT" == 201 ]]; then
  echo "PASS cross-process upsert race"
  exit 0
fi
echo "FAIL cross-process upsert race"
exit 1
