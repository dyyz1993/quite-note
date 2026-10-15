import json
import sys

try:
    payload = json.load(sys.stdin)
    if isinstance(payload, list) and payload:
        items = payload[0].get("SPDisplaysDataType", [])
    elif isinstance(payload, dict):
        gpu_rows = payload.get("SPDisplaysDataType", [])
        items = [display for row in gpu_rows for display in row.get("spdisplays_ndrvs", [])]
    else:
        items = []
except Exception:
    items = []

rows = []
for item in items:
    name = item.get("_name", "display")
    resolution = item.get("spdisplays_resolution") or item.get("_spdisplays_resolution") or "unknown"
    rows.append(f"{name}:{resolution}")
print("; ".join(rows))
