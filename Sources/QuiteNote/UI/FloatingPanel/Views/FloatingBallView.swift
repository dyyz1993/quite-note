import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 浮球视图 - 窗口缩小后的状态，支持拖拽、点击和状态动画
struct FloatingBallView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var focus: WindowFocusProvider
    /// 开发变体标识（com.quitenote.app.dev）：球用黄色，与正式版（深蓝）
    /// 同屏运行时一眼区分，避免误把测试数据写进生产库
    private static let isDevBuild = Bundle.main.bundleIdentifier == "com.quitenote.app.dev"
    @State private var hovering = false
    @State private var pasteSuccess = false
    @State private var aiSuccess = false
    @State private var iconOffset: CGFloat = 0
    @State private var aiRotation: Double = 0
    @State private var isDragging = false
    @State private var isTargeted = false // 拖拽是否悬停在上方

    var body: some View {
        ZStack {
            // Glow Effect - tight edge glow
            if hovering || store.isAIProcessing || pasteSuccess || aiSuccess || isTargeted {
                Circle()
                    .stroke(isTargeted ? Color.themeBlue500 : statusColor.opacity(0.8), lineWidth: 3)
                    .frame(width: 58, height: 58)
                    .blur(radius: isTargeted ? 5 : 3)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
                    .transition(.opacity)
            }

            // Main Ball - refined size 56
            Circle()
                .fill(ballBackgroundColor.opacity(isIdle ? 0.8 : 1.0))
                .frame(width: 56, height: 56)
                .scaleEffect(isTargeted ? 1.1 : 1.0)
                .shadow(color: Color.themeShadowBall, radius: 6, x: 0, y: 3)
                .overlay(
                    Circle()
                        .stroke(isTargeted ? Color.themeBlue500 : statusColor.opacity(0.3), lineWidth: 1)
                )

            // Icon with Animation
            Group {
                if store.isAIProcessing {
                    AISparkleIcon(size: 30, color: .themePurple500)
                        .rotationEffect(.degrees(aiRotation))
                        .onAppear {
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                aiRotation = 360
                            }
                        }
                } else if pasteSuccess || aiSuccess {
                    LucideView(name: .check, size: 30, color: .themeGreen500)
                        .transition(.scale.combined(with: .opacity))
                } else if isTargeted {
                    LucideView(name: .upload, size: 30, color: .themeBlue500)
                        .transition(.scale)
                } else {
                    AISparkleIcon(size: 30, color: statusColor)
                }
            }
            .offset(y: iconOffset)
            .scaleEffect(isTargeted ? 1.2 : 1.0)
        }
        .frame(width: 80, height: 80) // Container matches window size
        .contentShape(Circle())
        .onDrop(of: [.item, .fileURL, .text, .url], isTargeted: $isTargeted) { providers in
            // 使用统一的拖拽解析器
            DragDropParser.parse(providers: providers) { [weak store] result in
                guard let store = store else { return }

                if !result.isEmpty {
                    print("[DEBUG FloatingBallView] 接收到有效内容 - URLs: \(result.urls.count), Images: \(result.images.count)")

                    // 调用统一的处理方法（支持 URL 和图片）
                    store.handleDroppedContent(urls: result.urls, images: result.images)

                    // 浮球模式特有的 UI 反馈
                    if !result.images.isEmpty {
                        // 如果有图片，触发成功动画
                        triggerAISuccessAnimation()
                    }
                } else {
                    print("[DEBUG FloatingBallView] 未能解析到任何有效内容")
                }
            }
            return true
        }
        .onHover { h in
            hovering = h
            print("[DEBUG FloatingBallView] onHover - hovering: \(h), ballPosition: \(focus.ballPosition)")
            if h {
                // 跳动动画：向上移动然后轻微回弹
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 15).repeatForever(autoreverses: true)) {
                    iconOffset = -6
                }
                // 悬停即提示可拖动（affordance 先行）。macOS 公开 API 没有
                // 四向移动光标（系统私有），标准的"可抓取"光标是 openHand，
                // 拖动中切换 closedHand
                NSCursor.openHand.set()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    iconOffset = 0
                }
                // 拖动中鼠标可能被边缘钳制甩出窗口外，此时不清光标，松手后由下一次 hover 恢复
                if !isDragging {
                    NSCursor.arrow.set()
                }
            }
        }
        .onAppear {
            print("[DEBUG] FloatingBallView appeared, mode: \(focus.mode), statusColor: \(statusColor)")
        }
        .onReceive(store.$lastAISuccessAt) { _ in
            // 使用 store 的方法来判断是否应该显示成功动画
            if store.shouldShowAISuccessAnimation() {
                triggerAISuccessAnimation()
            }
        }
        .onReceive(store.$lastPasteSuccessAt) { _ in
            // 使用 store 的方法来判断是否应该显示粘贴成功动画
            if store.shouldShowPasteSuccessAnimation() {
                triggerPasteSuccessAnimation()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global) // 使用全局坐标
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        // 抓住：配合悬停时的 openHand，构成标准的抓取光标对；
                        // 用 set() 不用 push/pop，避免拖动中鼠标滑出窗口时光标栈失衡
                        NSCursor.closedHand.set()
                    }
                    // 直接使用鼠标的绝对屏幕坐标，这在多显示器环境下是最可靠的
                    let currentMouse = NSEvent.mouseLocation
                    QuiteNoteNotification.post(.updateBallPosition, object: currentMouse)
                }
                .onEnded { _ in
                    if isDragging {
                        isDragging = false
                        // 松手恢复：鼠标还在球上就回到 openHand，否则回箭头
                        NSCursor.arrow.set()
                        if hovering {
                            NSCursor.openHand.set()
                        }
                        // 吸附由控制器以 panel.frame 为准计算（避免视图侧位置状态过期）
                        QuiteNoteNotification.post(.snapBallToEdge)
                    }
                }
        )
        .onTapGesture {
            // 只有在非拖拽状态下的点击才触发展开
            if !isDragging {
                handleRestore()
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if store.isAIProcessing {
            return .themePurple500
        } else if pasteSuccess || aiSuccess {
            return .themeGreen500
        } else {
            // 开发变体：黄球上用深色图标/描边保证对比度；正式版保持淡蓝
            return Self.isDevBuild ? .themeDeepBlue : Color.themeStatusIdle
        }
    }

    private var ballBackgroundColor: Color {
        // 正式版深蓝 #0D111C；开发变体黄色（一眼区分 dev/生产，两者数据隔离）
        return Self.isDevBuild ? .themeYellow500 : .themeDeepBlue
    }

    private var isIdle: Bool {
        !hovering && !store.isAIProcessing && !pasteSuccess && !aiSuccess
    }

    // MARK: - Actions

    private func handleRestore() {
        QuiteNoteNotification.post(.restoreFromBall)
    }

    private func triggerAISuccessAnimation() {
        withAnimation(.spring()) {
            aiSuccess = true
        }
        HapticFeedbackManager.shared.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                aiSuccess = false
            }
        }
    }

    private func triggerPasteSuccessAnimation() {
        withAnimation(.spring()) {
            pasteSuccess = true
        }
        HapticFeedbackManager.shared.lightImpact()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                pasteSuccess = false
            }
        }
    }
}
