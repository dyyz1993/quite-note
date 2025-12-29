# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
3. **Record Store** (`RecordStore`) holds `@Published var records: [Record]`, auto-tags via `ContentClassifier`, debounced search (0.3s), pagination (loads 50 at a time, max 200 in-memory).
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

## Development Commands

### Build and Run
- **Build**: `swift build`
- **Run**: `swift run`
- **Test**: `swift test`
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
- Pagination: Loads 50 records at a time, max 200 in memory
- Memory warning notification triggers cleanup
- LazyVStack for efficient list rendering

## Tips for Development
- Use `print("[DEBUG] ...")` logging throughout for debugging
- LucideIcons bundle must be loaded from `Contents/Frameworks/`
- For multi-monitor setups, use "Force show & center" if window is lost
- AI summarization is async; UI updates must be on main thread
- CoreData uses auto-merge policy for concurrent updates
- 每次要去开发构建build-app.sh要用这个,禁止swift build