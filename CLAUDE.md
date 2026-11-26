# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

It is the tracked summary. The maintainer keeps the full local guide in `AGENTS.md` (not tracked, with `AGENTS-*.md` topic files); when that file is present its rules take precedence.

## Hard Rules

- **Build with `./build-app.sh`**, never a bare `swift build`: `--dev` builds the coexisting dev variant (`com.quitenote.app.dev`, isolated data), `--universal` builds Intel + Apple Silicon, `--install` updates the copy in `/Applications`. The script adds the compiler flags, resources and signing the app needs.
- **Run tests with `arch -arm64 /usr/bin/xcrun swift test`.** A bare `swift test` starts the test runner under Rosetta on Apple Silicon and hangs.
- **Never read or write production data from tests or debug builds**: `~/Library/Application Support/com.quitenote.app/`, `~/Library/Application Support/QuiteNote/QuiteNote.sqlite`, the `com.quitenote.app` defaults domain. Tests activate `TestStorageIsolation` (`QN_TEST_STORAGE_ROOT`); `StorageIsolationTests` guard this.
- **No UI automation on the developer's machine.** UI regression runs in CI on the dedicated test Mac (see "UI Automation" below). Never quit, relaunch or modify the production app in `/Applications`.
- **Choose signing identities by SHA-1 fingerprint**, never by display name.
- **Report "done" only after checking the produced artifact**, not the log: a step that degrades gracefully with `|| { echo skip; exit 0; }` looks the same as success.

## Overview

**QuiteNote** is a macOS menu bar application that captures clipboard text using a hardware Bluetooth button (BLE), stores and summarizes it with optional AI, and provides a floating panel for quick review and management. The app is built in Swift 5.9+ with SwiftUI for the floating panel UI, CoreBluetooth for BLE, CoreData for persistence, and OpenAI API integration for AI summarization.

## Core Architecture

### High-Level Flow
```
BLE Button Event (0x01=capture, 0x02=toggle)
    │
    ▼
BluetoothManager (peripheral discovery, event parsing, ACK)
    │ .bluetoothCaptureClipboard / .bluetoothToggleHistory notifications
    ▼
ClipboardService (NSPasteboard monitoring, SHA1 deduplication, source app detection)
    │ addRecord(content, hash, sourceApp, sourceUrl)
    ▼
RecordStore (in-memory [Record], CoreData sync, search, pagination)
    │ summarize(contextId, content, existingTags)
    ▼
AIService (request queue, max 3 concurrent, OpenAI Chat Completions)
    │ updateRecordAI(title, summary, tags, keywords)
    ▼
FloatingPanelController (NSPanel with SwiftUI, expanded/ball modes)
```

**Data Flow Summary:**
1. **BLE Button** (`BluetoothManager`) connects to GATT service `12345678-1234-5678-1234-567812345678`. Events: `0x01` → capture clipboard, `0x02` → toggle history.
2. **Clipboard Capture** (`ClipboardService`) monitors NSPasteboard, SHA1 hashing for deduplication, source app detection via `NSWorkspace.shared.frontmostApplication`, URL extraction.
3. **Record Store** (`RecordStore`) holds `@Published var records: [Record]`, auto-tags via `ContentClassifier`, debounced search (0.3s). The main list is a window over the database: first page of 100, +50 on scroll-to-bottom, at most 200 in memory (`canLoadMoreRecords` is the single source of truth). The in-panel search only covers loaded records; Markdown export reads the whole database.
4. **AI Service** (`AIService`) manages request queue (max 3 concurrent), deduplicates by contextId, JSON response `{"title","summary","confidence","tags","keywords"}`, API key in Keychain.
5. **UI** (`FloatingPanelController`) has two modes: **Expanded** (520x640) and **Floating Ball** (80x80), supports drag/lock, multi-monitor position persistence.
6. **Menu Bar** (`StatusBarController`) provides quick actions: toggle panel, capture, bulk summarize, export, preferences.
7. **Preferences** (`PreferencesManager`) stores settings in UserDefaults; API keys stored in `KeychainHelper`.

### Key Components

| Component | Location | Responsibilities |
|-----------|----------|------------------|
| **MainApp** | App/MainApp.swift | Service initialization, global paste event handling |
| **RecordStore** | Records/RecordStore.swift | Central store, AI orchestration, search, pagination, toast notifications |
| **BluetoothManager** | Bluetooth/BluetoothManager.swift | BLE connection, event parsing (0x01/0x02), ACK responses, 1s debouncing |
| **ClipboardService** | Clipboard/ClipboardService.swift | NSPasteboard monitoring, SHA1 deduplication, source app/URL detection |
| **AIService** | AI/AIService.swift | Request queue (max 3), OpenAI Chat Completions, JSON parsing |
| **FloatingPanelController** | UI/FloatingPanelController.swift | NSPanel management, expanded/ball modes, drag/lock, multi-monitor |
| **StatusBarController** | Menu/StatusBarController.swift | Menu bar icon, quick actions, Bluetooth status, record stats |
| **PreferencesManager** | Preferences/PreferencesManager.swift | UserDefaults wrapper, AI/config settings |
| **KeychainHelper** | Security/KeychainHelper.swift | Secure API key storage |
| **CoreDataStack** | Persistence/CoreDataStack.swift | Background task support, pagination queries, auto-merge policy |
| **ContentClassifier** | Utils/ContentClassifier.swift | Auto-tagging on record creation |
| **KeyboardShortcutManager** | Input/KeyboardShortcutManager.swift | Global hotkeys (⌥⌘R, ⌥⌘C, ⌥⌘A, etc.) |

### UI Views
- **FloatingRootView**: Root SwiftUI view with expanded/ball mode switching
- **FloatingBallView**: 80x80 draggable ball with status animations
- **RecordCardView**: Expandable cards with AI summary & keywords
- **HeatmapView**: Activity visualization in sidebar
- **SettingsOverlayView**: Preferences interface
- **EnhancedSearchBar**: Debounced search with history

### Theme System (Sources/QuiteNote/UI/Theme/)
- **Color+Theme.swift**: Dark mode palette (bg-gray-900, purple, blue)
- **Spacing+Theme.swift**: Scale (px2 to w64)
- **Font+Theme.swift**: Typography (themeH1, themeBody, etc.)
- **Animation+Theme.swift**: Duration constants (_150, _300, _500)
- **Shape+Theme.swift**: Corner radius and border configs

## UI Automation / Computer Use

Before running Quite Note UI tests, read `docs/ui-test-knowledge.md` and check `docs/ui-test-error-notebook.md`. `docs/ui-test-run-index.md` is the index of green runs; add or update its row after a passing run.

- UI regression runs in GitHub Actions (`.github/workflows/ui-smoke.yml`): the Dev app is built on the self-hosted macOS runner and `tools/ui-smoke` runs on the dedicated test Mac (`self-hosted, quitenote-ui`). Unit tests run in `test.yml`, `build-macos.yml` builds the DMG, `release.yml` signs, notarizes and publishes on `v*.*.*` tags.
- UI tests do not run on the developer's machine. Use CI or the dedicated test Mac.
- Only the dev variant `com.quitenote.app.dev` is tested, with a one-off `QN_TEST_STORAGE_ROOT`.
- Never commit the private host name, LAN address, or SSH details.
- Reuse `tools/ui-smoke/operations.json` and `tools/ui-smoke/selectors.json`; do not rediscover UI paths.
- Regressions: full smoke for tags/release/build changes; path-based incremental smoke for normal commits. `launch` and `cleanup` are always required.
- "All assertions passed" is not "it is visible": look at the real screenshots.
- FAIL/BLOCKED runs must generate `knowledge-candidate.md`; update the error notebook after triage.

## Development Commands

### Build and Run
- **Build**: `./build-app.sh --dev --no-launch` (see Hard Rules; no bare `swift build`)
- **Run**: the script launches the app unless `--no-launch` is given
- **Test**: `arch -arm64 /usr/bin/xcrun swift test`
- **Clean**: `rm -rf .build`
- **Format**: `swift format --in-place Sources/QuiteNote/**/*.swift`

### Development Environment
- Xcode 15+ (macOS 13+)
- Swift 5.9+ (as declared in Package.swift)
- Lucide-Swift icon library (auto-resolved via SwiftPM)

### Common Tasks
- Update UI in `FloatingRootView` (SwiftUI) and rebuild.
- Modify AI logic in `AIService`; test via Settings > AI.
- Adjust preferences via `PreferencesManager`; API keys via `KeychainHelper`.
- Add new menu actions in `StatusBarController`.
- Change BLE service/characteristics in `BluetoothManager` (UUIDs: `12345678-1234-5678-1234-567812345678`).
- Modify theme colors in `Color+Theme.swift`.

## Patterns & Conventions

### Thread Safety
- CoreData operations: Always use `NSManagedObjectContext.perform` or `performBackgroundTask`
- UI updates: Dispatch to `DispatchQueue.main.async`
- AI service uses request queue to limit concurrent operations (max 3)

### Notification Pattern
Custom notification names for cross-component communication:
- `.bluetoothCaptureClipboard`, `.bluetoothToggleHistory`
- `.showSettings`
- `.windowLockChanged`, `.animationsEnabledChanged`
- `.memoryOptimizationNeeded`

### Keyboard Shortcuts
- `⌥⌘R`: Toggle floating panel
- `⌥⌘⇧R`: Force show & center
- `⌥⌘C`: Capture clipboard
- `⌥⌘A`: Toggle AI
- `⌥⌘⇧A`: Bulk summarize (3 records)
- `⌥⌘E`: Export to Markdown
- `⌘,`: Open preferences
- `Cmd+V`: Global paste (when no text field focused)
- `ESC`: Close panel/collapse record (macOS 14+)

### Memory Management
- Main list window: first page of 100, +50 per scroll-to-bottom, at most 200 in memory
- Memory warning notification triggers cleanup
- LazyVStack for efficient list rendering

## Tips for Development
- Log key paths with `DiagnosticCenter.info/warning/error(category, message)`; bare `print` never reaches the diagnostics log users attach to feedback. Never log record content.
- LucideIcons bundle must be loaded from `Contents/Frameworks/`
- For multi-monitor setups, use "Force show & center" if window is lost
- AI summarization is async; UI updates must be on main thread
- CoreData uses auto-merge policy for concurrent updates
- 每次要去开发构建build-app.sh要用这个,禁止swift build