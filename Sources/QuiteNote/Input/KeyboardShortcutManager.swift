import AppKit

final class KeyboardShortcutManager {
    private var globalMonitor: Any?
    var onTogglePanel: (() -> Void)?
    var onToggleAI: (() -> Void)?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            let flags = e.modifierFlags
            if flags.contains(.command) && flags.contains(.option) {
                if e.characters?.lowercased() == "r" { self.onTogglePanel?() }
                if e.characters?.lowercased() == "a" { self.onToggleAI?() }
            }
        }
    }

    deinit { if let m = globalMonitor { NSEvent.removeMonitor(m) } }
}

