import AppKit
import SwiftUI

/// V2 选中预览控制器 - 显示选中区域和工具栏
/// 支持拖拽移动和调整尺寸
@MainActor
class V2SelectionPreviewController: NSObject {
    private var panel: NSPanel!
    private let snapshot: NSImage
    private let screen: NSScreen
    private let selectedRect: CGRect  // 初始选中区域的局部坐标
    private let onComplete: (CGRect) -> Void  // ⚠️ 修改：传递最终调整后的区域
    private let onCancel: () -> Void

    init(
        screen: NSScreen,
        snapshot: NSImage,
        selectedRect: CGRect,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.snapshot = snapshot
        self.selectedRect = selectedRect
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init()

        setupPanel()
    }

    private func setupPanel() {
        let screenFrame = screen.frame

        panel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.setFrame(screenFrame, display: false)

        let view = V2SelectionPreviewView(
            screen: screen,
            snapshot: snapshot,
            selectedRect: selectedRect,
            onCancel: { [weak self] in
                self?.handleCancel()
            },
            onSave: { [weak self] finalRect in
                self?.handleSave(finalRect: finalRect)
            }
        )

        let hostingController = NSHostingController(rootView: view)
        hostingController.view.frame = screenFrame
        hostingController.view.autoresizingMask = []

        panel.contentViewController = hostingController

        print("[V2SelectionPreviewController] 创建预览面板")
        print("  初始选中区域: \(selectedRect)")
    }

    func show() {
        print("[V2SelectionPreviewController] 显示预览面板")
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func handleSave(finalRect: CGRect) {
        print("[V2SelectionPreviewController] 用户确认保存")
        print("  最终选中区域: \(finalRect)")
        close()
        onComplete(finalRect)
    }

    private func handleCancel() {
        print("[V2SelectionPreviewController] 用户取消")
        close()
        onCancel()
    }

    func close() {
        panel.close()
    }

    deinit {
        let panelToClose = panel
        DispatchQueue.main.async {
            panelToClose?.close()
        }
    }
}
