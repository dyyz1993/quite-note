import AppKit
import SwiftUI

/// 截图预览窗口控制器
final class ScreenshotPreviewController: NSWindowController {
    private var hostingView: NSHostingView<ScreenshotPreviewView>?
    private var onSave: () -> Void
    private var onCancel: () -> Void
    
    init(image: NSImage, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        
        // 创建真正无边框透明面板
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.borderless, .nonactivatingPanel, .titled, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // 移除标题栏但保持 KeyWindow 特性
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // 由 SwiftUI 绘制内部投影，避免窗口边缘出现白边
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        
        super.init(window: panel)
        
        let contentView = ScreenshotPreviewView(
            image: image,
            onSave: { [weak self] in
                self?.close()
                onSave()
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            }
        )
        
        self.hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView
        
        // 居中显示
        panel.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
