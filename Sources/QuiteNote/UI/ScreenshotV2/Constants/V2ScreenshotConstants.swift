import SwiftUI

/// V2 截图功能相关常量
/// 整合了所有硬编码的布局、颜色、阈值、时间和字体常量

// MARK: - 布局常量
enum V2LayoutConstants {
    /// 手柄判定范围
    static let handleSize: CGFloat = 20

    /// 放大镜相关
    static let magnifierPadding: CGFloat = 20
    static let magnifierRadiusMultiplier: CGFloat = 2.5
    static let magnifierCircleLineWidth: CGFloat = 4
    static let sourceDotSize: CGFloat = 6
    static let connectionLineWidth: CGFloat = 1
    static let connectionLineDashPattern: [CGFloat] = [4, 2]

    /// 调试面板
    static let debugPanelWidth: CGFloat = 280
    static let windowsListHeight: CGFloat = 60

    /// 通用布局
    static let mainPadding: CGFloat = 40
    static let layerLabelPadding: CGFloat = 10
    static let layerLabelHorizontalPadding: CGFloat = 8
    static let layerLabelVerticalPadding: CGFloat = 4
}

// MARK: - 颜色常量
enum V2ColorConstants {
    /// 水印透明度
    static let watermarkOpacity: Double = 0.05

    /// 调试面板
    static let debugBackgroundOpacity: Double = 0.8
    static let debugBorderOpacity: Double = 0.5

    /// 活动状态
    static let activeStatusOpacity: Double = 0.3

    /// 叠加层
    static let overlayLineOpacity: Double = 0.5
    static let windowNameOpacity: Double = 0.8

    /// 交互层
    static let interactionLayerOpacity: Double = 0.0001

    /// 蒙层
    static let maskPrimaryOpacity: Double = 0.2
    static let maskInitialOpacity: Double = 0.3
    static let maskInactiveOpacity: Double = 0.5

    /// 吸附框
    static let snapBoxOpacity: Double = 0.8

    /// 层级标签
    static let layerLabelBackgroundOpacity: Double = 0.8
    static let layerLabelBorderOpacity: Double = 0.5

    /// 放大镜源点
    static let sourceDotAlpha: Double = 1.0
}

// MARK: - 阈值常量
enum V2ThresholdConstants {
    /// 窗口最小尺寸（宽高）
    static let minWindowSize: CGFloat = 100

    /// 点击判定距离阈值
    static let clickDistanceThreshold: CGFloat = 5

    /// 选区相关
    static let minSelectionSize: CGFloat = 5
    static let dragShowThreshold: CGFloat = 3

    /// 放大镜热区
    static let magnifierHotspotRadius: CGFloat = 15
    static let magnifierHotspotDiameter: CGFloat = 30

    /// 热区扩展
    static let elementHitTestExpansion: CGFloat = 10
    static let magnifierHitTestExpansion: CGFloat = 5

    /// 缩放
    static let zoomScale: CGFloat = 2.0

    /// 全屏选区内缩值
    static let insetValueForFullScreen: CGFloat = 2
}

// MARK: - 时间常量
enum V2TimeConstants {
    /// 透明度动画时长
    static let opacityAnimationDuration: Double = 0.2

    /// 挖孔动画时长
    static let holeAnimationDuration: Double = 0.15

    /// 吸附框动画时长
    static let snapBoxAnimationDuration: Double = 0.15
}

// MARK: - 字体常量
enum V2FontConstants {
    /// 字体大小
    static let watermarkSize: CGFloat = 100
    static let screenTitleSize: CGFloat = 18
    static let logTextSize: CGFloat = 10
    static let windowNameSize: CGFloat = 9
    static let layerLabelTitleSize: CGFloat = 10
    static let layerLabelSubtitleSize: CGFloat = 10

    /// 圆角半径
    static let cornerRadiusForPanel: CGFloat = 12
    static let cornerRadiusForLayerLabel: CGFloat = 6
    static let activeStatusCornerRadius: CGFloat = 4
}
