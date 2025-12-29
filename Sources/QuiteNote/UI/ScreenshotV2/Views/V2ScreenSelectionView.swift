import SwiftUI
import AppKit

/// V2 屏幕选择视图 - 为每个屏幕创建独立的面板显示静态截图
struct V2ScreenSelectionView: View {
    @ObservedObject var state: V2CaptureState
    let onSelectScreen: (NSScreen) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // 显示所有屏幕的截图
            ForEach(Array(state.screenSnapshots.keys.enumerated()), id: \.offset) { _, screen in
                if let snapshot = state.screenSnapshots[screen] {
                    V2ScreenSnapshotView(
                        screen: screen,
                        snapshot: snapshot,
                        onSelect: { onSelectScreen(screen) }
                    )
                }
            }

            // 提示信息（只在主屏幕显示）
            if NSScreen.main != nil {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Text("选择要截图的屏幕")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(8)

                                HStack(spacing: 16) {
                                    Label("点击选择屏幕", systemImage: "rectangle.on.rectangle")
                                    Label("ESC 取消", systemImage: "escape")
                                }
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)
                            }
                            .padding(.bottom, 40)
                            .padding(.trailing, 40)
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .onAppear {
            print("[DEBUG V2ScreenSelectionView] 屏幕选择界面已显示")
        }
    }
}

/// 单个屏幕截图视图
struct V2ScreenSnapshotView: View {
    let screen: NSScreen
    let snapshot: NSImage
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            // 获取屏幕的全局边界
            let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) ?? screen.frame

            ZStack {
                // 静态截图
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // 悬停高亮
                if isHovered {
                    Color.blue.opacity(0.3)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                }

                // 屏幕标签
                VStack {
                    HStack {
                        Text(screen.localizedName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: screenBounds.width, height: screenBounds.height)
            .position(x: screenBounds.midX, y: screenBounds.midY)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                print("[DEBUG V2ScreenSnapshotView] 选中屏幕: \(screen.localizedName)")
                onSelect()
            }
        }
    }
}

#Preview {
    V2ScreenSelectionView(
        state: V2CaptureState(),
        onSelectScreen: { _ in },
        onCancel: {}
    )
}
