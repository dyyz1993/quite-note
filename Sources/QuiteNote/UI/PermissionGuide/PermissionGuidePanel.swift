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
            [NSDraggingImageComponent(key: .icon, contents: icon)]
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
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

/// 权限引导视图：可拖拽应用图标到系统设置列表 + 一键跳转
struct PermissionGuideView: View {
    var onRetry: () -> Void

    @State private var screenGranted = ScreenshotService.shared.checkScreenCapturePermission()
    @State private var showError = false
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            // 标题区
            VStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40))
                    .foregroundColor(.themeBlue600)

                Text("需要「屏幕录制」权限")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Text("截图功能需要此权限才能捕获屏幕内容，开启后不会再重复询问。")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            // 步骤引导
            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: 1, text: "点击下方「打开系统设置」按钮")
                stepRow(number: 2, text: "把下面的应用图标按住拖进列表，或点列表下方的 ➕ 添加")
                stepRow(number: 3, text: "打开列表中「Quite Note」的开关，然后回到这里")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            // 可拖拽的应用图标（原生拖拽会话，与 Finder 同机制）
            HStack(spacing: 14) {
                DraggableAppIconView(appURL: Bundle.main.bundleURL)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("⬆︎ 按住图标拖到设置列表")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Text("松手后点击开关开启权限")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                Spacer()
            }
            .padding(16)
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

            if showError {
                Text("还没有检测到权限，请确认开关已经打开")
                    .font(.themeCaption)
                    .foregroundColor(.themeStatusError)
            }

            Text("如果系统提示「退出并重新打开」，请点击同意，否则截图可能仍是灰屏。")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // 按钮区
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                        .font(.themeBody)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    if ScreenshotService.shared.checkScreenCapturePermission() {
                        onRetry()
                    } else {
                        screenGranted = false
                        showError = true
                    }
                } label: {
                    Text(screenGranted ? "✅ 开始截图" : "已开启，重新截图")
                        .font(.themeBody)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 460, height: 500)
        .background(Color.themePanel)
        .onReceive(timer) { _ in
            let granted = ScreenshotService.shared.checkScreenCapturePermission()
            if granted != screenGranted {
                screenGranted = granted
                if granted { showError = false }
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.themeBlue600))

            Text(text)
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
