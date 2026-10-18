#!/bin/zsh
set -euo pipefail

REPORT="${1:-$HOME/Library/Application Support/com.quitenote.app.dev/CoreService/24h-monitor.csv}"
MIN_DURATION_SECONDS="${QN_CORE_REPORT_MIN_DURATION:-86400}"
MAX_SAMPLE_GAP_SECONDS="${QN_CORE_REPORT_MAX_GAP:-1200}"
MAX_HEARTBEAT_AGE_SECONDS="${QN_CORE_REPORT_MAX_HEARTBEAT_AGE:-5}"
MAX_RSS_GROWTH_KB="${QN_CORE_REPORT_MAX_RSS_GROWTH:-20480}"
MAX_WAL_BYTES="${QN_CORE_REPORT_MAX_WAL:-52428800}"

if [[ "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: $0 [monitor.csv]

Fails closed until the CSV covers 24 hours with healthy samples.
Tunable environment thresholds:
  QN_CORE_REPORT_MIN_DURATION (default 86400)
  QN_CORE_REPORT_MAX_GAP (default 1200)
  QN_CORE_REPORT_MAX_HEARTBEAT_AGE (default 5)
  QN_CORE_REPORT_MAX_RSS_GROWTH (default 20480 KB)
  QN_CORE_REPORT_MAX_WAL (default 52428800 bytes)
EOF
  exit 0
fi

[[ -f "$REPORT" ]] || { echo "FAIL missing report: $REPORT" >&2; exit 1; }

python3 - "$REPORT" "$MIN_DURATION_SECONDS" "$MAX_SAMPLE_GAP_SECONDS" \
  "$MAX_HEARTBEAT_AGE_SECONDS" "$MAX_RSS_GROWTH_KB" "$MAX_WAL_BYTES" <<'PY'
import csv
import sys
from datetime import datetime, timedelta, timezone

path = sys.argv[1]
min_duration = int(sys.argv[2])
max_gap = int(sys.argv[3])
max_heartbeat_age = int(sys.argv[4])
max_rss_growth = int(sys.argv[5])
max_wal = int(sys.argv[6])

failures = []
with open(path, newline="") as handle:
    rows = list(csv.DictReader(handle))

def timestamp(row):
    return datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))

if len(rows) < 2:
    failures.append("not-enough-samples")
else:
    duration = int((timestamp(rows[-1]) - timestamp(rows[0])).total_seconds())
    if duration < min_duration:
        failures.append(f"duration={duration}s<required={min_duration}s")

    gaps = [
        int((timestamp(right) - timestamp(left)).total_seconds())
        for left, right in zip(rows, rows[1:])
    ]
    if not gaps or max(gaps) > max_gap:
        worst_gap = max(gaps, default=0)
        failures.append(f"sample-gap={worst_gap}s>allowed={max_gap}s")

if any(row["state_running"] != "true" for row in rows):
    failures.append("state-reported-not-running")

if any(not row["pid"].isdigit() for row in rows):
    failures.append("missing-pid")

pid_values = [row["pid"] for row in rows if row["pid"].isdigit()]
if len(pid_values) != len(rows):
    failures.append("missing-pid-samples")
elif len(set(pid_values)) != 1:
    failures.append(f"pid-changed range={min(pid_values, key=int)}..{max(pid_values, key=int)}")

run_values = [int(row["runs"]) for row in rows if row["runs"].isdigit()]
if not run_values or max(run_values) != min(run_values):
    failures.append(f"launchd-restarts-detected range={min(run_values, default=0)}..{max(run_values, default=0)}")

bad_heartbeats = [
    row for row in rows
    if not row["heartbeat_age_seconds"].isdigit()
    or int(row["heartbeat_age_seconds"]) > max_heartbeat_age
]
if bad_heartbeats:
    failures.append(f"stale-heartbeat-samples={len(bad_heartbeats)}")

rss_values = [int(row["rss_kb"]) for row in rows if row["rss_kb"].isdigit()]
if len(rss_values) != len(rows):
    failures.append("missing-rss-samples")
elif max(rss_values) - rss_values[0] > max_rss_growth:
    failures.append(f"rss-growth={max(rss_values)-rss_values[0]}KB>allowed={max_rss_growth}KB")

cpu_values = [float(row["cpu_percent"]) for row in rows if row["cpu_percent"]]
if len(cpu_values) != len(rows):
    failures.append("missing-cpu-samples")

wal_values = [int(row["wal_bytes"]) for row in rows if row["wal_bytes"].isdigit()]
if len(wal_values) != len(rows):
    failures.append("missing-wal-samples")
elif max(wal_values) > max_wal:
    failures.append(f"wal-max={max(wal_values)}B>allowed={max_wal}B")

captured = [int(row["captured_count"]) for row in rows if row["captured_count"].isdigit()]
if len(captured) != len(rows):
    failures.append("missing-captured-count")
elif any(right < left for left, right in zip(captured, captured[1:])):
    failures.append("captured-count-decreased")

errors = [row["last_error"] for row in rows if row["last_error"]]
if errors:
    unique_errors = sorted(set(errors))
    failures.append(f"errors={';'.join(unique_errors)}")

if rows:
    start = timestamp(rows[0])
    last = timestamp(rows[-1])
    duration = int((last - start).total_seconds())
    remaining = max(0, min_duration - duration)
    eta = last + timedelta(seconds=remaining)
    print(f"report={path}")
    print(f"samples={len(rows)}")
    print(f"duration_seconds={duration}")
    print(f"remaining_seconds={remaining}")
    print(f"eta_utc={eta.isoformat().replace('+00:00', 'Z')}")
    print(f"runs={min(run_values, default=0)}..{max(run_values, default=0)}")
    print(f"rss_kb={min(rss_values, default=0)}..{max(rss_values, default=0)}")
    print(f"cpu_percent_average={sum(cpu_values)/len(cpu_values) if cpu_values else 0:.3f}")
    print(f"wal_bytes=max({max(wal_values, default=0)})")
    print(f"captured_count={captured[0] if captured else 0}..{captured[-1] if captured else 0}")

if failures:
    print("FAIL " + ", ".join(failures))
    sys.exit(1)
print("PASS 24h acceptance evidence")
PY
