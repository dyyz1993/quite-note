import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Captures deterministic pixel evidence from the app's own TCC context.
/// It is enabled only for isolated UI smoke runs, so normal users never enter it.
enum UIEvidenceCaptureService {
    static func captureIfNeeded() {
        guard ProcessInfo.processInfo.environment["QN_UI_EVIDENCE_DIR"] != nil else { return }

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let image = CGDisplayCreateImage(displayID) else { continue }
            let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QN_UI_EVIDENCE_DIR"] ?? "/tmp")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("app-\(displayID)-\(ProcessInfo.processInfo.processIdentifier)-\(Int(Date().timeIntervalSince1970 * 1000)).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            _ = CGImageDestinationFinalize(destination)
        }
    }
}
