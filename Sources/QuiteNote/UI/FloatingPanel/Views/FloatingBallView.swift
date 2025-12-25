import SwiftUI
import AppKit

/// 浮球视图 - 窗口缩小后的状态，支持拖拽、点击和状态动画
struct FloatingBallView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var focus: WindowFocusProvider
    @State private var hovering = false
    @State private var pasteSuccess = false
    @State private var aiSuccess = false
    @State private var iconOffset: CGFloat = 0
    @State private var aiRotation: Double = 0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            // Glow Effect - tight edge glow
            if hovering || store.isAIProcessing || pasteSuccess || aiSuccess {
                Circle()
                    .stroke(statusColor.opacity(0.8), lineWidth: 3)
                    .frame(width: 58, height: 58)
                    .blur(radius: 3)
                    .transition(.opacity)
            }

            // Main Ball - refined size 56
            Circle()
                .fill(ballBackgroundColor.opacity(isIdle ? 0.8 : 1.0))
                .frame(width: 56, height: 56)
                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
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
                } else {
                    AISparkleIcon(size: 30, color: statusColor)
                }
            }
            .offset(y: iconOffset)
        }
        .frame(width: 80, height: 80) // Container matches window size
        .contentShape(Circle())
        .onHover { h in
            hovering = h
            if h {
                // 跳动动画：向上移动然后轻微回弹
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 15).repeatForever(autoreverses: true)) {
                    iconOffset = -6
                }
                NSCursor.pointingHand.set()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    iconOffset = 0
                }
                NSCursor.arrow.set()
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
                        NSCursor.closedHand.push()
                    }
                    // 直接使用鼠标的绝对屏幕坐标，这在多显示器环境下是最可靠的
                    let currentMouse = NSEvent.mouseLocation
                    QuiteNoteNotification.post(.updateBallPosition, object: currentMouse)
                }
                .onEnded { _ in
                    if isDragging {
                        isDragging = false
                        NSCursor.pop()
                        snapToEdge()
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
            // 用户要求：闲置时淡蓝色且带透明度
            return Color.themeBlue400.opacity(0.7)
        }
    }

    private var ballBackgroundColor: Color {
        // 浮球背景色始终使用要求的深蓝色 #0D111C
        return .themeDeepBlue
    }

    private var isIdle: Bool {
        !hovering && !store.isAIProcessing && !pasteSuccess && !aiSuccess
    }

    // MARK: - Actions

    private func snapToEdge() {
        // 获取包含当前窗口中心点的屏幕
        let currentBallPos = focus.ballPosition
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(currentBallPos, $0.frame, false) } ?? NSScreen.main ?? screens.first!

        let screenFrame = targetScreen.visibleFrame
        let padding: CGFloat = 16
        let ballRadius: CGFloat = 28 // 56/2
        var finalPos = currentBallPos

        // 在当前所在的屏幕内进行边界吸附
        if finalPos.x < screenFrame.minX + padding + ballRadius {
            finalPos.x = screenFrame.minX + padding + ballRadius
        } else if finalPos.x > screenFrame.maxX - padding - ballRadius {
            finalPos.x = screenFrame.maxX - padding - ballRadius
        }

        if finalPos.y < screenFrame.minY + padding + ballRadius {
            finalPos.y = screenFrame.minY + padding + ballRadius
        } else if finalPos.y > screenFrame.maxY - padding - ballRadius {
            finalPos.y = screenFrame.maxY - padding - ballRadius
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            QuiteNoteNotification.post(.updateBallPosition, object: finalPos)
        }
    }

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
