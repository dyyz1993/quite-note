import AppKit
import SwiftUI

/// 简单蒙层测试工具 - 用于诊断权限和面板配置问题
/// 不依赖窗口识别逻辑，直接显示黑色半透明蒙层
class SimpleMaskTest {

    static func show() {
        print("[SimpleMaskTest] ========== 开始简单蒙层测试 ==========")

        // 1. 检查权限
        let hasPermission = CGPreflightScreenCaptureAccess()
        print("[SimpleMaskTest] 屏幕录制权限: \(hasPermission)")

        if !hasPermission {
            print("[SimpleMaskTest] ❌ 没有屏幕录制权限，尝试请求...")
            let granted = CGRequestScreenCaptureAccess()
            print("[SimpleMaskTest] 权限请求结果: \(granted)")

            if !granted {
                print("[SimpleMaskTest] ❌ 权限被拒绝，无法继续测试")
                return
            }
        }

        // 2. 获取主屏幕
        guard let screen = NSScreen.main else {
            print("[SimpleMaskTest] ❌ 无法获取主屏幕")
            return
        }

        print("[SimpleMaskTest] 主屏幕: \(screen.localizedName)")
        print("[SimpleMaskTest] 屏幕尺寸: \(screen.frame.width) x \(screen.frame.height)")

        // 3. 创建面板
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // 4. 配置面板
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]

        // 5. 强制设置面板 frame
        panel.setFrame(screen.frame, display: false)

        print("[SimpleMaskTest] 面板已创建，frame: \(panel.frame)")

        // 6. 创建 SwiftUI 视图
        let rootView = SimpleMaskTestView { [weak panel] in
            print("[SimpleMaskTest] 用户点击关闭")
            panel?.close()
        }

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = screen.frame
        hostingController.view.autoresizingMask = []

        panel.contentViewController = hostingController

        // 7. 显示面板
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        print("[SimpleMaskTest] ✅ 蒙层已显示")
        print("[SimpleMaskTest] 提示: 点击任意位置关闭，或等待 5 秒自动关闭")

        // 8. 5秒后自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if panel.isVisible {
                print("[SimpleMaskTest] 自动关闭蒙层")
                panel.close()
            }
        }
    }
}

/// 简单蒙层视图
struct SimpleMaskTestView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // 黑色半透明蒙层
            Color.black.opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    onClose()
                }

            // 提示文本
            VStack(spacing: 16) {
                Text("蒙层测试")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("如果能看到这个，说明权限和面板配置正确")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))

                Text("点击任意位置关闭，或等待 5 秒")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
