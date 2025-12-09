# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**QuiteNote** is a macOS menu bar application that captures clipboard text using a hardware Bluetooth button (BLE), stores and summarizes it with optional AI, and provides a floating panel for quick review and management. The app is built in Swift with SwiftUI for the floating panel UI, CoreBluetooth for BLE, CoreData for persistence, and a lightweight local AI service.

## Core Architecture

### High-Level Flow
1. **BLE Button** (`BluetoothManager`) scans and connects to a custom GATT service. It listens for `CHAR_BUTTON_EVT` notifications and writes ACKs back via `CHAR_ACK`.
2. **Clipboard Capture** (`ClipboardService`) observes the system pasteboard and writes new text to the store. It supports optional deduplication (10-minute window) and updates timestamps for recent duplicates.
3. **Record Store** (`RecordStore`) holds an in-memory array of `Record`s, manages CoreData sync, and coordinates AI summarization. It emits light hints and toast notifications.
4. **AI Service** (`AIService`) provides a unified protocol to summarize content. It can route to a local rule-based summarizer or an OpenAI backend (API key stored in Keychain). Results are persisted and UI-updated.
5. **UI** (`FloatingPanelController`, `FloatingRootView`) shows a floating panel with a list of records, a heatmap, and a settings overlay. The panel is an NSPanel that can be toggled, force-centered, and locked.
6. **Menu Bar** (`StatusBarController`) provides quick actions and status, including a preferences shortcut.
7. **Preferences** (`PreferencesManager`) persists user settings in UserDefaults; API keys are stored in Keychain.

### Key Components
- **RecordStore** (Sources/QuiteNote/Records/RecordStore.swift): Central store, AI orchestration, notifications.
- **BluetoothManager** (Sources/QuiteNote/Bluetooth/BluetoothManager.swift): BLE connection, event handling, ACK.
- **ClipboardService** (Sources/QuiteNote/Clipboard/ClipboardService.swift): Pasteboard monitoring, deduplication.
- **AIService** (Sources/QuiteNote/AI/AIService.swift): AI protocol and providers (local/OpenAI).
- **FloatingPanelController** (Sources/QuiteNote/UI/FloatingPanelController.swift): NSPanel management, animations, drag/lock.
- **StatusBarController** (Sources/QuiteNote/Menu/StatusBarController.swift): Menu bar icon, quick actions.
- **PreferencesManager** (Sources/QuiteNote/Preferences/PreferencesManager.swift): UserDefaults and Keychain helpers.
- **CoreData** (Sources/QuiteNote/Persistence/): `CoreDataStack` and `CDRecord` for persistence.

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
- Modify AI logic in `AIService` and test with both local and OpenAI providers.
- Adjust preferences via `PreferencesManager`; API keys via `KeychainHelper`.
- Add new menu actions in `StatusBarController`.
- Change BLE service/characteristics in `BluetoothManager` (UUIDs, event parsing).

## Tips for Development
- Use the debug prints in `AppDelegate` and `BluetoothManager` to trace BLE events and window toggles.
- The floating panel supports drag and lock; test with `forceCenterWindow` and `windowLock` preference.
- AI summarization is async; ensure UI updates on the main thread.
- CoreData is managed by `CoreDataStack.shared`; always use `NSManagedObjectContext.perform` for thread safety.

## Support and Documentation
- See the docs/ directory for test plans and feasibility docs.
- Note.jsx is a React mockup for UI reference (not part of the Swift codebase).