//
//  UpdateProgressBadge.swift
//  QuiteNote
//
//  主面板顶栏的更新按钮。
//

import SwiftUI

/// 主面板顶栏的更新按钮。视图树保持静态，各层只切 opacity（主面板里不做内容切换动画）：
/// - 有新版本、还没开始下载：蓝色上箭头圆钮
/// - 下载中：外圈是圆环进度条，中间是百分比
/// - 解压 / 安装中：圆环走满，中间转圈
/// - 等用户在 Sparkle 的窗口里点「安装并重新启动」：圆环走满，中间回到上箭头
struct UpdateProgressBadge: View {
    let phase: UpdateDownloadPhase

    /// 平时的圆钮直径
    static let idleDiameter: CGFloat = 22
    /// 圆环直径：比圆钮大一点，"100%" 才放得下
    static let ringDiameter: CGFloat = 26
    private static let ringWidth: CGFloat = 2.5

    private var isIdle: Bool { phase == .idle }

    /// 圆环画到哪；总长度还不知道时留空（中间转圈）
    private var ringFraction: Double { UpdateProgressMath.fraction(for: phase) ?? 0 }

    var body: some View {
        ZStack {
            idleBadge
                .opacity(isIdle ? 1 : 0)
                .animation(.easeOut(duration: ThemeDuration._200.rawValue), value: isIdle)
            progressRing
                .opacity(isIdle ? 0 : 1)
                .animation(.easeOut(duration: ThemeDuration._200.rawValue), value: isIdle)
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
    }

    private var idleBadge: some View {
        ZStack {
            Circle()
                .fill(Color.themeOverlaySelected)
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: Self.idleDiameter, height: Self.idleDiameter)
    }

    private var progressRing: some View {
        ZStack {
            // 描边内缩半个线宽，圆环外缘正好贴着 26pt 的边
            Circle()
                .inset(by: Self.ringWidth / 2)
                .stroke(Color.themeBorder, lineWidth: Self.ringWidth)
            Circle()
                .inset(by: Self.ringWidth / 2)
                .trim(from: 0, to: ringFraction)
                .stroke(Color.themeOverlaySelected,
                        style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: ThemeDuration._200.rawValue), value: ringFraction)
            center
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
    }

    /// 圆环中间：有百分比就显示百分比（瞬时切换，不做动画）
    @ViewBuilder private var center: some View {
        if let percent = UpdateProgressMath.percentText(for: phase) {
            Text(verbatim: percent)
                .font(.themeCaptionTiny.weight(.semibold))
                .foregroundColor(.themeTextPrimary)
                .lineLimit(1)
                // 限制在圆环内圈里："100%" 才不会压到环上
                .frame(maxWidth: Self.ringDiameter - Self.ringWidth * 2 - 3)
                .minimumScaleFactor(0.6)
        } else if phase == .readyToInstall {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.themeTextPrimary)
        } else {
            // 还不知道总长度 / 解压 / 安装中：小转圈
            MiniSpinner()
        }
    }

    /// 纯 SwiftUI 的小转圈：系统的 ProgressView 放不进这么小的圆心，也没法离屏渲染验证
    private struct MiniSpinner: View {
        @State private var isSpinning = false

        var body: some View {
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Color.themeTextSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(.spin, value: isSpinning)
                .onAppear { isSpinning = true }
        }
    }
}
