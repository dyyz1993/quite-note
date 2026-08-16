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
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 22))
                .foregroundColor(granted ? .themeStatusSuccess : .themeTextTertiary)

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
