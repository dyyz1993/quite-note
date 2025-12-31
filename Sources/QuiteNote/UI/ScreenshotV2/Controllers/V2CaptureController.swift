import AppKit
import SwiftUI

/// V2 静态截图主控制器 - 协调整个截图流程
/// 修复了多屏幕窗口识别问题
@MainActor
class V2CaptureController: NSObject {

    static let shared = V2CaptureController()

    private var screenSelectionController: V2ScreenSelectionController?
    private var selectionPreviewController: V2SelectionPreviewController?

    // 回调
    var onComplete: ((NSImage) -> Void)?
    var onCancel: (() -> Void)?
    
    // ⚠️ 新增：用于在截图开始前隐藏主窗口，截图结束后恢复
    var onWillStart: (() -> Void)?
    var onDidFinish: (() -> Void)?

    private override init() {
        super.init()
    }

 /// 开始 V2 截图流程
    func startCapture() {
        print("[V2CaptureController] ========== 开始 V2 静态截图流程 ==========")
        
        // 1. 清理可能存在的旧控制器和面板
        screenSelectionController?.close()
        screenSelectionController = nil
        selectionPreviewController?.close()
        selectionPreviewController = nil
        
        // ⚠️ 同时关闭可能存在的调试面板
        V2ScreenshotDebugController.close()
        
        // ⚠️ 重置全局状态，确保每次截图都是干净的
        V2PrimaryScreenStateManager.shared.reset()
        
        onWillStart?()
         
        // 2. 创建屏幕选择控制器
        // 延时一小会儿，确保窗口已经消失在屏幕缓冲区
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            
            // 3. 打印屏幕信息用于调试
            V2ScreenCaptureService.shared.printAllScreensInfo()

            // 4. 显示屏幕/窗口选择界面
            self.showScreenSelection()
        }
    }

    /// 停止并清理当前截图流程
    func stopCapture() {
        print("[V2CaptureController] 停止截图流程")
        screenSelectionController?.close()
        screenSelectionController = nil
        selectionPreviewController?.close()
        selectionPreviewController = nil
        onDidFinish?()
    }

    private func showScreenSelection() {
        print("[V2CaptureController] 显示屏幕/窗口选择界面")

        let controller = V2ScreenSelectionController.create(
            onSelectScreen: { [weak self] screen in
                Task { @MainActor in
                    self?.handleScreenSelected(screen)
                }
            },
            onSelectWindow: { [weak self] window in
                Task { @MainActor in
                    self?.handleWindowSelected(window)
                }
            },
            onSelectArea: { [weak self] rect, screen in
                Task { @MainActor in
                    self?.handleAreaSelected(rect, screen: screen)
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    self?.handleCancel()
                }
            }
        )

        screenSelectionController = controller
        controller.show()
    }

    private func handleScreenSelected(_ screen: NSScreen) {
        print("[V2CaptureController] 选中屏幕: \(screen.localizedName)")

        // 获取屏幕截图
        guard let snapshot = V2ScreenCaptureService.shared.captureScreen(screen) else {
            print("[ERROR V2CaptureController] 找不到屏幕截图")
            return
        }

        // 全屏模式：直接保存
        let result = V2CaptureResult(
            image: snapshot,
            screen: screen,
            initialCropRect: nil,
            mode: .fullscreen
        )

        completeWithResult(result)
    }

    private func handleWindowSelected(_ window: WindowInfo) {
        print("[V2CaptureController] 选中窗口: \(window.displayTitle)")
        print("  窗口全局坐标: \(window.bounds)")

        // 从窗口位置找到对应的屏幕
        let windowCenter = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let screen = V2CoordinateMapper.findScreenContaining(point: windowCenter)
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        print("  窗口所在屏幕: \(screen.localizedName)")

        guard let snapshot = V2ScreenCaptureService.shared.captureScreen(screen) else {
            print("[ERROR V2CaptureController] 找不到屏幕截图")
            return
        }

        // 转换窗口坐标到屏幕局部坐标
        guard let localRect = V2CoordinateMapper.screenToLocal(rect: window.bounds, on: screen) else {
            print("[ERROR V2CaptureController] 坐标转换失败")
            return
        }

        print("  窗口局部坐标: \(localRect)")
        print("  截图尺寸: \(snapshot.size)")

        // ⚠️ 修复：显示工具栏界面，而不是直接保存
        showSelectionPreview(screen: screen, snapshot: snapshot, selectedRect: localRect)
    }

    private func handleAreaSelected(_ rect: CGRect, screen: NSScreen) {
        print("[V2CaptureController] 选中区域: \(rect)")

        guard let snapshot = V2ScreenCaptureService.shared.captureScreen(screen) else {
            print("[ERROR V2CaptureController] 找不到屏幕截图")
            return
        }

        // ⚠️ 修复：显示工具栏界面，而不是直接保存
        showSelectionPreview(screen: screen, snapshot: snapshot, selectedRect: rect)
    }

    /// 显示选中预览界面（带工具栏）
    private func showSelectionPreview(screen: NSScreen, snapshot: NSImage, selectedRect: CGRect) {
        print("[V2CaptureController] 显示选中预览界面")

        let controller = V2SelectionPreviewController(
            screen: screen,
            snapshot: snapshot,
            selectedRect: selectedRect,
            onComplete: { [weak self] finalRect in
                self?.completeWithSelection(screen: screen, snapshot: snapshot, selectedRect: finalRect)
            },
            onCancel: { [weak self] in
                self?.handlePreviewCancel()
            }
        )

        selectionPreviewController = controller
        controller.show()
    }

    /// 预览确认后完成截图
    private func completeWithSelection(screen: NSScreen, snapshot: NSImage, selectedRect: CGRect) {
        // 裁剪选中区域
        let croppedImage = cropImage(snapshot, to: selectedRect)

        let result = V2CaptureResult(
            image: croppedImage,
            screen: screen,
            initialCropRect: selectedRect,
            mode: .window
        )

        completeWithResult(result)
    }

    /// 裁剪图片
    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage {
        let imageSize = image.size
        let croppedRect = CGRect(
            x: rect.origin.x,
            y: imageSize.height - rect.origin.y - rect.height,  // 翻转Y坐标
            width: rect.width,
            height: rect.height
        )

        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()
        image.draw(
            in: CGRect(origin: .zero, size: rect.size),
            from: croppedRect,
            operation: .copy,
            fraction: 1.0
        )
        croppedImage.unlockFocus()

        return croppedImage
    }

    /// 预览取消
    private func handlePreviewCancel() {
        print("[V2CaptureController] 预览取消，返回屏幕选择界面")
        selectionPreviewController = nil
        // 可以选择重新显示屏幕选择界面，或者完全取消
        // 目前选择完全取消
        handleCancel()
    }

    private func completeWithResult(_ result: V2CaptureResult) {
        print("[V2CaptureController] 截图完成")
        print("  模式: \(result.mode)")
        print("  屏幕: \(result.screen.localizedName)")
        print("  图片尺寸: \(result.image.size)")
        if let cropRect = result.initialCropRect {
            print("  裁剪区域: \(cropRect)")
        }

        // TODO: 这里可以添加预览步骤
        // 目前直接完成
        onComplete?(result.image)

        cleanup()
    }

    private func handleCancel() {
        print("[V2CaptureController] 用户取消")
        onCancel?()
        cleanup()
    }

    private func cleanup() {
        print("[V2CaptureController] 清理资源")
        screenSelectionController = nil
        selectionPreviewController = nil
        
        // 5. 通知流程已结束（用于恢复主窗口）
        onDidFinish?()
    }
}
