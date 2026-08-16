import SwiftUI
import AppKit

/// 可拖拽的应用图标（原生 NSView 实现，与 Finder 拖拽同机制）
///
/// SwiftUI 的 .onDrag 提供的数据格式系统设置授权列表不接收；
/// 必须用 NSDraggingSession + NSURL 作为 pasteboard writer 才能拖进去。
struct DraggableAppIconView: NSViewRepresentable {
    let appURL: URL

    func makeNSView(context: Context) -> DraggableAppIconNSView {
        let view = DraggableAppIconNSView()
        view.fileURL = appURL
        view.image = NSWorkspace.shared.icon(forFile: appURL.path)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ nsView: DraggableAppIconNSView, context: Context) {}
}

final class DraggableAppIconNSView: NSImageView, NSDraggingSource {
    var fileURL: URL?
    private var dragStartEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        dragStartEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartEvent, let url = fileURL else { return }

        // 位移超过阈值才启动拖拽会话，避免误触
        let p0 = convert(start.locationInWindow, from: nil)
        let p1 = convert(event.locationInWindow, from: nil)
        guard hypot(p1.x - p0.x, p1.y - p0.y) > 4 else { return }

        // NSURL 作为 pasteboard writer = 与 Finder 拖拽文件完全一致的数据格式
        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        // ⚠️ 关键：必须设置拖拽跟随图标和 frame，否则 beginDraggingSession 会抛
        // NSInvalidArgumentException（崩溃栈定位过：-[NSDraggingItem setDraggingFrame:]）
        let icon = image ?? NSWorkspace.shared.icon(forFile: url.path)
        draggingItem.draggingFrame = NSRect(x: 0, y: 0, width: 48, height: 48)
        draggingItem.imageComponentsProvider = {
            let component = NSDraggingImageComponent(key: .icon)
            component.contents = icon
            return [component]
        }
        beginDraggingSession(with: [draggingItem], event: start, source: self)
        dragStartEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}

/// 权限引导悬浮窗控制器
/// 在截图触发但缺少「屏幕录制」权限时显示，引导用户完成授权
@MainActor
final class PermissionGuideController {
    static let shared = PermissionGuideController()
    private var panel: NSPanel?

    func show() {
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = PermissionGuideView {
            PermissionGuideController.shared.close()
            ScreenshotService.shared.startScreenshot()
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        p.title = "屏幕录制权限"
        p.contentView = NSHostingView(rootView: view)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        // 关键修复：跟随所有空间显示——用户在别的桌面/全屏应用里触发截图时，
        // 面板也能出现在当前空间，而不是弹在别的 Space 里看不见
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.center()
        panel = p

        // 先激活应用再显示，确保面板浮到最前
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        DiagnosticCenter.info("Permission", "权限引导窗已展示")
    }

    func close() {
        panel?.orderOut(nil)
    }
}

/// 权限引导视图：双权限统一引导（先辅助功能，后屏幕录制）+ 可拖拽应用图标
struct PermissionGuideView: View {
    var onRetry: () -> Void

    @State private var screenGranted = ScreenshotService.shared.checkScreenCapturePermission()
    @State private var accessibilityGranted = ScreenshotService.shared.checkAccessibilityPermission()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var allGranted: Bool { screenGranted && accessibilityGranted }

    var body: some View {
        VStack(spacing: 14) {
            // 标题区
            VStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 34))
                    .foregroundColor(.themeBlue600)

                Text("完成两项权限授权")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Text("建议按 ① → ② 顺序授权；都开启后此窗口不再出现")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
            .padding(.top, 8)

            // ① 辅助功能（先授权：立即生效，无需重启）
            permissionRow(
                order: "①",
                title: "辅助功能",
                subtitle: "全局快捷键需要 · 授权立即生效，无需重启",
                granted: accessibilityGranted,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )

            // ② 屏幕录制（最后授权：系统会要求退出重开，放最后避免打断）
            permissionRow(
                order: "②",
                title: "屏幕录制",
                subtitle: "截图功能需要 · 授权后系统会要求「退出并重新打开」，请点同意",
                granted: screenGranted,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )

            // 可拖拽的应用图标（两个授权列表通用）
            HStack(spacing: 14) {
                DraggableAppIconView(appURL: Bundle.main.bundleURL)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("⬆︎ 按住图标，拖进对应权限的列表")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Text("两项各拖一次即可（或点列表 ➕ 从应用程序里选）")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.themeCard)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.themeBlue600, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            )
            .padding(.horizontal, 24)

            // 保底路径：从 Finder 拖拽是系统保证兼容的方式
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            } label: {
                Label("拖不进去？点这里在 Finder 中显示应用，从 Finder 拖", systemImage: "magnifyingglass")
                    .font(.themeCaption)
            }
            .buttonStyle(.link)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // 主按钮：状态自动刷新，全通过后可完成
            Button {
                if allGranted {
                    onRetry()
                }
            } label: {
                Text(allGranted ? "✅ 已全部授权，开始使用" : "去授权后回到这里，状态每 1.5 秒自动刷新…")
                    .font(.themeBody)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allGranted)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 460, height: 560)
        .background(Color.themePanel)
        .onReceive(timer) { _ in
            let screen = ScreenshotService.shared.checkScreenCapturePermission()
            let accessibility = ScreenshotService.shared.checkAccessibilityPermission()
            if screen != screenGranted { screenGranted = screen }
            if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        }
    }

    private func permissionRow(order: String, title: String, subtitle: String, granted: Bool, settingsURL: String) -> some View {
        HStack(spacing: 12) {
            // 待授权状态图标呼吸闪烁，主动吸引注意
            Group {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.themeStatusSuccess)
                } else {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 22))
                        .foregroundColor(.themeBlue600)
                        .modifier(PendingPulse())
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(order) \(title)")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Text(subtitle)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            if !granted {
                Button {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("去授权")
                        .font(.themeCaption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.themeBlue600)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.themeCard)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorderSubtle))
        .padding(.horizontal, 24)
    }
}

/// 待授权图标的呼吸闪烁效果（opacity 0.35~1.0 循环）
struct PendingPulse: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - 迷你拖拽引导横条（贴合系统设置窗口底部的轻量引导）

/// 迷你横条控制器：一条贴在系统设置窗口底部的小横条，
/// 虚线框 + 呼吸图标提示"从这里拖进上方授权列表"，跟随设置窗口移动
@MainActor
final class MiniPermissionBarController {
    static let shared = MiniPermissionBarController()
    private var panel: NSPanel?
    private var followTimer: Timer?
    private var missCount = 0

    private let barSize = NSSize(width: 320, height: 64)

    func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: barSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .statusBar          // 压在系统设置之上
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: MiniPermissionBarView {
                MiniPermissionBarController.shared.hide()
            })
            panel = p
        }

        // 初始位置：设置窗口找不到时先放主屏底部中央
        if !reposition() {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            panel?.setFrameOrigin(NSPoint(x: screen.midX - barSize.width / 2, y: screen.minY + 20))
        }
        panel?.orderFrontRegardless()
        missCount = 0
        startFollowing()
        DiagnosticCenter.info("Permission", "迷你拖拽引导条已展示")
    }

    func hide() {
        panel?.orderOut(nil)
        followTimer?.invalidate()
        followTimer = nil
    }

    private func startFollowing() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                MiniPermissionBarController.shared.followTick()
            }
        }
    }

    private func followTick() {
        // 设置窗口消失后宽限 8 秒（等待打开/切换页面），仍找不到才收起横条
        if reposition() {
            missCount = 0
        } else {
            missCount += 1
            if missCount > 8 {
                hide()
            }
        }
    }

    /// 贴合系统设置窗口底部；找到窗口返回 true
    @discardableResult
    private func reposition() -> Bool {
        guard let panel, let settingsFrame = Self.findSettingsWindowFrame() else { return false }

        var x = settingsFrame.midX - barSize.width / 2
        var y = settingsFrame.minY - barSize.height - 10
        if y < 40 {
            // 窗口贴屏幕底时，横条改贴窗口内侧底部
            y = settingsFrame.minY + 12
        }
        // 限制在所在屏幕的可视范围内
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: settingsFrame.midX, y: settingsFrame.midY)) }) {
            x = max(screen.visibleFrame.minX, min(screen.visibleFrame.maxX - barSize.width, x))
            y = max(screen.visibleFrame.minY, y)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        return true
    }

    /// 查找系统设置主窗口（CG 全局坐标 → AppKit 坐标转换）
    /// 注意：无屏幕录制权限时读不到窗口属主名，返回 nil（调用方有兜底定位）
    nonisolated private static func findSettingsWindowFrame() -> NSRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let appNames = ["System Settings", "系统设置", "System Preferences", "系统偏好设置"]

        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  appNames.contains(owner) else { continue }
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
               let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double,
               w > 300, h > 300 {
                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                // CG 坐标原点在主屏左上，AppKit 在主屏左下
                return NSRect(x: x, y: mainHeight - y - h, width: w, height: h)
            }
        }
        return nil
    }
}

/// 迷你横条视图：虚线框呼吸拖拽图标 + 双权限状态点 + 关闭按钮
struct MiniPermissionBarView: View {
    var onClose: () -> Void

    @State private var a11yGranted = ScreenshotService.shared.checkAccessibilityPermission()
    @State private var screenGranted = ScreenshotService.shared.checkScreenCapturePermission()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            // 虚线框 + 呼吸效果的拖拽图标
            DraggableAppIconView(appURL: Bundle.main.bundleURL)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.themeBlue600, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
                .modifier(PendingPulse())

            VStack(alignment: .leading, spacing: 4) {
                Text("按住拖进上方的授权列表")
                    .font(.themeBody)
                    .foregroundColor(.white)
                HStack(spacing: 10) {
                    statusDot(label: "辅助功能", granted: a11yGranted)
                    statusDot(label: "屏幕录制", granted: screenGranted)
                }
            }
            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 64)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().stroke(Color.themeBlue600.opacity(0.6)))
        .onReceive(timer) { _ in
            a11yGranted = ScreenshotService.shared.checkAccessibilityPermission()
            screenGranted = ScreenshotService.shared.checkScreenCapturePermission()
            // 双权限齐了自动收起
            if a11yGranted && screenGranted {
                onClose()
            }
        }
    }

    private func statusDot(label: String, granted: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(granted ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}
