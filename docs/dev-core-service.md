# Quite Note Dev Core Service

## Goal

`QuiteNoteCoreService` is the resident clipboard-history core used by the Dev
variant only. It keeps capturing clipboard text while the Dev App is closed,
writes to the isolated Debug SQLite database, and is supervised by launchd.

This service is **not** enabled for production until the Dev 24-hour acceptance
report passes.

## Safety boundaries

- LaunchAgent label: `com.quitenote.app.dev.core`
- Executable: `~/Library/Application Support/com.quitenote.app.dev/CoreService/quitenote-core`
- Database: `~/Library/Application Support/QuiteNote-Debug/ClipboardHistory-Debug.sqlite`
- State: `~/Library/Application Support/com.quitenote.app.dev/CoreService/state.json`
- Log: `~/Library/Application Support/com.quitenote.app.dev/CoreService/launchd.log`

The manager and plist deliberately reject the production paths:

- `~/Library/Application Support/QuiteNote/ClipboardHistory.sqlite`
- any production QuiteNote CoreData database

## Lifecycle

Build both Dev applications first:

```zsh
./build-app.sh --dev --no-launch
```

Install or replace the resident core:

```zsh
./tools/manage-quitenote-dev-core.sh install
```

Other commands:

```zsh
./tools/manage-quitenote-dev-core.sh status
./tools/manage-quitenote-dev-core.sh restart
./tools/manage-quitenote-dev-core.sh verify
./tools/manage-quitenote-dev-core.sh uninstall
```

`verify` intentionally sends `SIGKILL` to the current core and requires launchd
to provide a new PID. Do not run it while collecting 24-hour evidence; it will
appear as an intentional restart.

## In-App status

The Dev-only clipboard settings section reads `state.json` and launchd state,
then shows:

- running status and PID
- captured count
- last captured time
- isolated database path
- heartbeat check time
- write/storage errors

The App never launches a second core. Recovery uses launchd's managed service
via `kickstart -k`.

## Failure behavior

- Missing/corrupt state file: App reports unhealthy state and offers managed restart.
- Stale heartbeat: App reports unhealthy state and offers managed restart.
- SQLite write failure: repository rolls back and reports the error; Core stays
  alive and records `lastError`; App shows the storage/write error.
- Store open/migration failure: persistence exposes the localized load error,
  and the clipboard settings page shows a read-only/degraded storage warning.

## 24-hour acceptance

Start a clean observation only after installing the core:

```zsh
./tools/manage-quitenote-dev-core.sh monitor-start
```

Check progress:

```zsh
./tools/manage-quitenote-dev-core.sh monitor-status
```

After at least 24 hours, generate the verdict:

```zsh
./tools/manage-quitenote-dev-core.sh report
```

The report fails closed unless all of the following are true:

- CSV spans at least 86,400 seconds
- no sample gap exceeds the configured maximum
- launchd `runs` never changes
- every sample has a PID and healthy heartbeat
- RSS growth stays below the configured threshold
- WAL stays below the configured maximum
- captured count never decreases
- no state/storage error is present

Default thresholds:

| Threshold | Default |
|---|---:|
| minimum duration | 86,400 seconds |
| maximum sample gap | 1,200 seconds |
| maximum heartbeat age | 5 seconds |
| maximum RSS growth | 20,480 KB |
| maximum WAL | 52,428,800 bytes |

The default monitor samples every 600 seconds for 90,000 seconds. Override only
for a shorter test run:

```zsh
QN_CORE_MONITOR_INTERVAL=60 \
QN_CORE_MONITOR_DURATION=3600 \
./tools/manage-quitenote-dev-core.sh monitor-start
```

## Concurrency proof

The manual two-process race proves the App/Core write contract:

```zsh
QN_CORE_CROSS_PROCESS_SMOKE=1 \
arch -arm64 /usr/bin/xcrun swift test \
  --filter ClipboardHistoryRepositoryTests/testTwoCoreProcessesConcurrentlyUpsertSameContentWithoutDuplicates
```

Expected result:

```text
shared_rows=1
unique_rows=200
total_rows=201
PASS cross-process upsert race
```
