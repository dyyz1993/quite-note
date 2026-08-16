import SwiftUI
import AppKit

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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
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

            // 可拖拽的应用图标
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 52, height: 52)
                    .onDrag {
                        // 拖拽提供 .app 文件，可直接拖入系统设置的授权列表
                        NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider()
                    }
                    .help("按住我拖到系统设置的应用列表里")

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
        .frame(width: 460, height: 470)
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
