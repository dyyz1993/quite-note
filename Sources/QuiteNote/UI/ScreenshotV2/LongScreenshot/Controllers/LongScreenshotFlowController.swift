import Foundation
import AppKit
import os.log
import _Concurrency
import SwiftUI

private let logger = Logger(subsystem: "com.quitenote.app", category: "LongScreenshotFlow")

/// 长截图流程控制器
/// 负责管理长截图的完整流程，协调各个服务
/// 简化版本：只保留 UI 框架和帧采集，不做拼接
class LongScreenshotFlowController {
    static let shared = LongScreenshotFlowController()

    private var scrollDetectionService: ScrollDetectionService?
    private var capturedFrames: [NSImage] = []
    private var capturedFramePaths: [URL] = []
    private var tempDirectory: URL?
    private var selection: CGRect = .zero
    private var screen: NSScreen?
    private var config: CaptureConfig = .default
    private var totalScrollDistance: CGFloat = 0
    private var completion: ((Result<NSImage, Error>) -> Void)?

    private init() {}

    /// ✨ 新增：独立启动长截图流程（不依赖主视图）
    /// 从普通截图模式的"长图"按钮启动
    @MainActor
    static func startIndependently(
        selection: CGRect,
        targetScreen: NSScreen?,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        logger.info("独立启动长截图流程")

        let sourceScreen = V2PrimaryScreenStateManager.shared.selectionScreen

        // ✅ 修复双工具栏问题：立即清除普通模式的状态，确保工具栏隐藏
        V2PrimaryScreenStateManager.shared.selectedArea = nil
        V2PrimaryScreenStateManager.shared.globalHoveredRect = nil
        logger.info("已清除普通截图模式的状态（防止双工具栏）")

        let screen = targetScreen ?? sourceScreen ?? NSScreen.screens.first ?? NSScreen.main!

        logger.info("选区所在屏幕: \(screen.localizedName)")
        logger.info("选区坐标（局部）: \(selection.debugDescription, privacy: .public)")

        V2PrimaryScreenStateManager.shared.setCapturing(false)
        V2PrimaryScreenStateManager.shared.setLongScreenshotMode(true)

        // 3. 关闭主视图（在创建新面板前）
        V2ScreenshotController.close()

        // ✨ 使用 WindowCoordinator 创建独立窗口（三窗口架构）
        LongScreenshotWindowCoordinator.shared.showAllWindows(
            selection: selection,
            screen: screen
        )

        // 5. ✅ 修复：不立即开始采集，等待用户点击"开始滚动"按钮
        let controller = LongScreenshotFlowController.shared
        controller.selection = selection
        controller.screen = screen
        controller.completion = completion

        logger.info("长截图窗口已显示，等待用户点击开始按钮")
    }

    /// 开始长截图捕获
    @MainActor
    func startCapture(
        selection: CGRect,
        screen: NSScreen,
        config: CaptureConfig = .default,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        logger.info("开始长截图流程")

        self.selection = selection
        self.screen = screen
        self.config = config
        self.completion = completion
        self.capturedFrames = []
        self.capturedFramePaths = []
        self.totalScrollDistance = 0

        // ✅ 新增：初始化滚动偏移和选区高度
        V2PrimaryScreenStateManager.shared.currentScrollOffset = 0
        V2PrimaryScreenStateManager.shared.longScreenshotSelectionHeight = selection.height

        // 创建临时文件夹用于保存每一帧
        createTempDirectory()

        // ⚠️ 关键：设置 selectedArea，确保工具栏和预览能正常工作
        V2PrimaryScreenStateManager.shared.selectedArea = selection
        V2PrimaryScreenStateManager.shared.setLongScreenshotMode(true)
        V2PrimaryScreenStateManager.shared.setCapturing(true)
        V2PrimaryScreenStateManager.shared.longScreenshotPreviews = []

        // ✨ 三窗口架构：选区覆盖层已自动设置 ignoresMouseEvents = true
        logger.info("三窗口架构已激活 - 选区覆盖层穿透，工具栏独立")

        // ✅ 修复采样率问题：添加启动延迟，让用户有时间准备好
        Task {
            // 等待 300ms 让用户准备好滚动
            try? await Task.sleep(nanoseconds: 300_000_000)

            // 检查是否还在捕获状态（用户可能已取消）
            guard V2PrimaryScreenStateManager.shared.isCapturing else {
                logger.info("用户已取消，不开始捕获")
                return
            }

            // 截取第一帧（异步）
            await captureFirstFrame()

            // 启动滚动检测
            startScrollDetection()
        }
    }

    /// 停止捕获并保存原始帧
    @MainActor
    func stopCapture() async {
        logger.info("停止捕获，保存原始帧")

        // 1. 停止滚动检测
        scrollDetectionService?.stopMonitoring()
        scrollDetectionService = nil

        // 2. 关闭窗口
        LongScreenshotWindowCoordinator.shared.closeAllWindows()

        // 延迟清空状态，给窗口关闭动画一些时间
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            V2PrimaryScreenStateManager.shared.setCapturing(false)
            V2PrimaryScreenStateManager.shared.setLongScreenshotMode(false)
        }

        // 3. 检查是否有足够的帧
        guard !capturedFrames.isEmpty else {
            logger.error("没有捕获到任何帧")
            completion?(.failure(LongScreenshotError.noFrames))
            cleanupTempDirectory()
            return
        }

        // 4. 保存原始帧（不拼接）
        logger.info("已捕获 \(self.capturedFrames.count) 帧，保存到临时文件夹")

        if let tempDir = tempDirectory {
            NSWorkspace.shared.open(tempDir)
        }

        // 返回最后一帧作为结果
        completion?(.success(capturedFrames.last!))

        // 清理临时文件夹（延迟清理，给用户时间查看）
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            self.cleanupTempDirectory()
        }

        // ✅ 拼接完成后清空预览数据
        V2PrimaryScreenStateManager.shared.longScreenshotPreviews = []
    }

    /// 取消捕获
    @MainActor
    func cancelCapture() {
        logger.info("取消捕获")

        scrollDetectionService?.stopMonitoring()
        scrollDetectionService = nil

        capturedFrames.removeAll()
        capturedFramePaths.removeAll()
        totalScrollDistance = 0

        // ✅ 修复预览图消失问题：先关闭窗口，再清空数据
        LongScreenshotWindowCoordinator.shared.closeAllWindows()

        // 延迟清空状态，给窗口关闭动画一些时间
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            V2PrimaryScreenStateManager.shared.setCapturing(false)
            V2PrimaryScreenStateManager.shared.longScreenshotPreviews = []
            V2PrimaryScreenStateManager.shared.setLongScreenshotMode(false)
        }

        // 立即清理临时文件夹
        cleanupTempDirectory()

        completion?(.failure(LongScreenshotError.cancelled))
    }

    // MARK: - 私有方法

    /// 截取第一帧（异步）
    @MainActor
    private func captureFirstFrame() async {
        guard let screen = screen else {
            logger.error("屏幕为空")
            return
        }

        logger.info("截取第一帧")

        // ✅ 截图前隐藏 UI（防止线框和工具栏被捕获）
        await LongScreenshotWindowCoordinator.shared.hideUIForCapture()

        // ✅ 同步捕获，避免异步复杂度
        let image = V2ScreenshotController.captureScreen(screen)

        // ✅ 截图后恢复 UI
        LongScreenshotWindowCoordinator.shared.showUIAfterCapture()

        // 裁剪到选区
        if let cropped = cropImage(image, to: selection) {
            capturedFrames.append(cropped)
            V2PrimaryScreenStateManager.shared.longScreenshotPreviews.append(cropped)

            // ✅ 新增：记录第一帧的滚动位置（索引 0，偏移量为 0）
            V2PrimaryScreenStateManager.shared.frameScrollPositions[0] = 0

            // 实时保存到磁盘
            saveFrame(cropped, index: 0)

            logger.info("第一帧已添加并保存，预览更新")

            // ✅ 修复预览面板问题：第一帧捕获成功后再显示预览面板
            LongScreenshotWindowCoordinator.shared.showPreviewPanel()
        } else {
            logger.error("第一帧裁剪失败")
        }
    }

    /// 启动滚动检测
    @MainActor
    private func startScrollDetection() {
        let service = ScrollDetectionService()
        self.scrollDetectionService = service

        service.startMonitoring(
            selection: selection,
            screen: screen!,
            threshold: config.scrollThreshold
        ) { [weak self] in
            Task { @MainActor in
                await self?.onScrollThresholdReached()
            }
        }
    }

    /// 滚动阈值达到时的回调
    @MainActor
    private func onScrollThresholdReached() async {
        logger.info("达到滚动阈值，截取新帧")

        guard let screen = screen else { return }

        // 检查帧数限制
        if capturedFrames.count >= config.maxFrames {
            logger.info("达到最大帧数限制，自动停止")
            await stopCapture()
            return
        }

        // ✅ 截图前隐藏 UI（防止线框和工具栏被捕获）
        await LongScreenshotWindowCoordinator.shared.hideUIForCapture()

        // 截取新帧
        let image = V2ScreenshotController.captureScreen(screen)

        // ✅ 截图后恢复 UI
        LongScreenshotWindowCoordinator.shared.showUIAfterCapture()

        guard let cropped = cropImage(image, to: selection) else {
            logger.error("图片裁剪失败，跳过此次捕获")
            return
        }

        // 添加新帧
        let frameIndex = capturedFrames.count

        capturedFrames.append(cropped)
        V2PrimaryScreenStateManager.shared.longScreenshotPreviews.append(cropped)

        // 实时保存到磁盘
        saveFrame(cropped, index: frameIndex)

        // ✅ 新增：更新滚动偏移量（用于显示视口指示器）
        let overlap = selection.height * config.captureOverlapPercentage
        let effectiveScroll = config.scrollThreshold - overlap
        let currentOffset = CGFloat(frameIndex) * effectiveScroll
        V2PrimaryScreenStateManager.shared.currentScrollOffset = currentOffset

        // ✅ 新增：记录当前帧的滚动位置
        V2PrimaryScreenStateManager.shared.frameScrollPositions[frameIndex] = currentOffset

        totalScrollDistance += config.scrollThreshold
        logger.info("新帧已添加并保存，当前帧数: \(self.capturedFrames.count)，滚动偏移: \(currentOffset)")
    }

    /// 裁剪图片到指定区域
    @MainActor
    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("无法获取 CGImage")
            return nil
        }

        let scale = screen?.backingScaleFactor ?? 1.0

        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            logger.error("CGImage 裁剪失败，rect: \(String(describing: pixelRect))")
            return nil
        }

        let result = NSImage(size: rect.size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: croppedCGImage, size: rect.size).draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        result.unlockFocus()

        logger.debug("裁剪成功，原始尺寸: \(String(describing: image.size))，裁剪后: \(String(describing: result.size))")
        return result
    }

    // MARK: - 文件管理辅助方法

    /// 创建临时文件夹
    @MainActor
    private func createTempDirectory() {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiteNote")
            .appendingPathComponent("LongScreenshot")

        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let sessionDir = tempBase.appendingPathComponent("\(timestamp)")

        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            self.tempDirectory = sessionDir
            logger.info("创建临时文件夹: \(sessionDir.path)")
        } catch {
            logger.error("创建临时文件夹失败: \(error.localizedDescription)")
        }
    }

    /// 保存单帧到磁盘
    @MainActor
    private func saveFrame(_ image: NSImage, index: Int) {
        guard let tempDir = tempDirectory else {
            logger.warning("临时文件夹未创建，无法保存帧")
            return
        }

        let fileName = String(format: "frame_%03d.png", index)
        let fileURL = tempDir.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.error("图片数据转换失败")
            return
        }

        do {
            try pngData.write(to: fileURL)
            capturedFramePaths.append(fileURL)
            logger.info("已保存第 \(index) 帧到: \(fileURL.path)")
        } catch {
            logger.error("保存帧失败: \(error.localizedDescription)")
        }
    }

    /// 清理临时文件夹
    @MainActor
    private func cleanupTempDirectory() {
        guard let tempDir = tempDirectory else { return }

        do {
            try FileManager.default.removeItem(at: tempDir)
            logger.info("已清理临时文件夹: \(tempDir.path)")
        } catch {
            logger.warning("清理临时文件夹失败: \(error.localizedDescription)")
        }

        tempDirectory = nil
        capturedFramePaths.removeAll()
    }
}

/// 长截图错误类型
enum LongScreenshotError: LocalizedError {
    case noFrames
    case cancelled
    case stitchFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFrames:
            return "没有捕获到任何帧"
        case .cancelled:
            return "用户取消操作"
        case .stitchFailed(let message):
            return "拼接失败: \(message)"
        }
    }
}
