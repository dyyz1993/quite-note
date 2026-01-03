# 智能滚动截图拼接系统

## 概述

这是一个全新的智能滚动截图拼接系统，采用逐行匹配、复杂度检测和质量可视化技术，提供更精准的拼接效果和更好的用户体验。

## 核心特性

### 1. 逐行/逐块匹配

不再整张图对比，而是将图像分成多个水平条带（每块 30px 高）分别匹配：

- 只在特征丰富的区域进行匹配
- 跳过纯色区域（复杂度 < 0.3）
- 每个条带独立计算偏移
- 加权平均得到最终偏移

### 2. 纹理复杂度检测

使用 Sobel 边缘检测算法计算每个条带的纹理复杂度：

- **0.0-0.3**: 纯色/弱纹理 → 跳过
- **0.3-0.7**: 中等纹理 → 可用
- **0.7-1.0**: 强纹理 → 优先

```swift
// 复杂度计算示例
let complexity = await calculateStripComplexity(strip)
if complexity >= 0.3 {
    // 使用此条带进行匹配
}
```

### 3. 混合算法架构

根据图像复杂度自动选择最佳策略：

| 策略 | 适用场景 | 特点 |
|------|---------|------|
| **Vision** | 高复杂度区域 | 基于特征点匹配，准确率最高 |
| **MSE** | 中等复杂度区域 | 基于像素差异，速度快 |
| **Fixed** | 低复杂度区域 | 固定重叠百分比，最简单 |

```swift
// 自动选择策略
let result = await IntelligentStitchingService.shared.stitch(
    images,
    captureOverlap: 0.30,
    forceStrategy: nil  // nil = 自动选择
)

// 强制使用特定策略
let result = await IntelligentStitchingService.shared.stitch(
    images,
    captureOverlap: 0.30,
    forceStrategy: .vision  // 强制使用视觉匹配
)
```

### 4. 质量监控和可视化

实时监控每个条带的匹配质量，在预览图上标记问题区域：

#### 质量问题类型

| 类型 | 图标 | 说明 |
|------|------|------|
| **低置信度** | ⚠️ | 置信度低于 70% |
| **偏移异常** | 📏 | 偏移量超过 ±15px |
| **模糊** | 🌫️ | 图像模糊 |
| **复杂区域** | 🎨 | 复杂区域匹配不佳 |
| **纯色区域** | 🔲 | 纯色区域可能导致对齐不准确 |
| **匹配失败** | ❌ | 完全匹配失败 |

#### 严重程度

- **高** (🔴): 需要修复，会影响拼接效果
- **中** (🟠): 建议修复，可能影响拼接效果
- **低** (🟡): 可选修复，影响较小

### 5. 位置追踪系统

追踪用户当前滚动位置，在预览图上显示视口指示器，提供回滚建议：

```swift
// 更新当前位置
ViewportTracker.shared.updatePosition(scrollOffset: 500)

// 显示视口指示器
ViewportTracker.shared.showIndicatorOnPreview(
    previewImage: preview,
    hostingRect: rect
)

// 计算回滚建议
let suggestion = ViewportTracker.shared.calculateRollbackSuggestion(
    for: issue,
    frameHeight: 800
)
```

## 使用方法

### 基础使用

```swift
// 使用默认配置
let config = CaptureConfig.default

// 开始长截图捕获
await LongScreenshotFlowController.shared.startCapture(
    selection: selectionRect,
    screen: targetScreen,
    config: config
) { result in
    switch result {
    case .success(let image):
        // 拼接成功
        print("拼接完成: \(image.size)")
    case .failure(let error):
        // 拼接失败
        print("错误: \(error.localizedDescription)")
    }
}
```

### 高级配置

```swift
// 使用纯智能拼接配置（最高质量）
let config = CaptureConfig.intelligent

// 自定义配置
let customConfig = CaptureConfig(
    scrollThreshold: 500,
    autoDetectEnabled: true,
    maxFrames: 50,
    enablePixelDetection: false,
    pixelChangeThreshold: 0.03,
    pixelDownsampleSize: 200,
    pixelDetectionFallbackEnabled: true,
    captureOverlapPercentage: 0.30,      // 30% 重叠
    enableSmartAlignment: false,          // 禁用旧系统
    alignmentConfig: .default,
    enableIntelligentStitching: true,     // 启用新系统
    defaultStitchingStrategy: .vision     // 强制使用视觉匹配
)
```

### 质量报告

拼接完成后，系统会自动生成质量报告：

```
╔═══════════════════════════════════════════════════════════════╗
║                    智能拼接质量报告                            ║
╚═══════════════════════════════════════════════════════════════╝

📊 基本信息
────────────────────────────────────────────────────────────
策略:          视觉特征匹配
帧数:          10
条带数:        150
总体置信度:    85%
质量等级:      ✅ 优秀
处理时间:      2.50s

📋 问题统计
────────────────────────────────────────────────────────────
总问题数:      2
严重问题:      0 🔴
中等问题:      1 🟠
轻微问题:      1 🟡

⚠️  问题详情
────────────────────────────────────────────────────────────
1. 条带 #5
   位置: Y = 500px
   类型: ⚠️ 低置信度
   严重: 高
   置信度: 40%

2. 条带 #8
   位置: Y = 800px
   类型: 📏 偏移异常
   严重: 中
   置信度: 60%
```

### 修复质量问题

1. **查看问题详情**
   - 点击预览图上的问题标记
   - 或在质量报告中点击"查看详情"

2. **查看回滚建议**
   - 系统会自动计算回滚位置
   - 显示预期改善程度

3. **执行回滚和重新采集**
   - 滚回到建议位置
   - 重新采集该区域
   - 系统会自动替换问题帧

## API 参考

### IntelligentStitchingService

核心拼接服务，负责逐行匹配和复杂度检测。

```swift
actor IntelligentStitchingService {
    static let shared = IntelligentStitchingService()

    /// 智能拼接图片
    func stitch(
        _ images: [NSImage],
        captureOverlap: CGFloat = 0.10,
        forceStrategy: StitchingStrategy? = nil
    ) async -> IntelligentStitchResult
}
```

### StitchingQualityMonitor

质量监控服务，负责分析拼接结果并生成报告。

```swift
actor StitchingQualityMonitor {
    static let shared = StitchingQualityMonitor()

    /// 分析拼接结果
    func analyzeQuality(result: IntelligentStitchResult) async -> [StitchingQualityIssue]

    /// 生成质量报告
    func generateQualityReport(result: IntelligentStitchResult) async -> String

    /// 在预览图上标记问题
    func markIssuesOnPreview(
        _ preview: NSImage,
        issues: [StitchingQualityIssue],
        scale: CGFloat = 1.0
    ) async -> NSImage

    /// 生成回滚建议
    func generateRollbackSuggestions(
        issues: [StitchingQualityIssue],
        totalHeight: CGFloat
    ) async -> [RollbackSuggestion]
}
```

### ViewportTracker

视口追踪服务，负责追踪当前位置和显示指示器。

```swift
@MainActor
class ViewportTracker: ObservableObject {
    static let shared = ViewportTracker()

    /// 更新当前位置
    func updatePosition(scrollOffset: CGFloat)

    /// 显示视口指示器
    func showIndicatorOnPreview(
        previewImage: NSImage,
        hostingRect: CGRect
    )

    /// 隐藏视口指示器
    func hideIndicator()

    /// 滚动到问题区域
    func scrollToIssue(_ issue: StitchingQualityIssue)

    /// 计算回滚建议
    func calculateRollbackSuggestion(
        for issue: StitchingQualityIssue,
        frameHeight: CGFloat
    ) -> RollbackSuggestion
}
```

## 性能优化

### 复杂度检测优化

- 使用降采样加速（200px 宽度）
- 只计算重叠区域的复杂度
- 跳过低复杂度条带

### 匹配优化

- 两阶段搜索（粗搜索 + 精搜索）
- 粗搜索步长 4px，精搜索步长 1px
- 搜索范围 ±10px

### 内存优化

- 逐帧处理，不一次性加载所有帧
- 使用 actor 隔离确保线程安全
- 及时释放临时资源

## 故障排除

### 问题：拼接后出现重复内容

**原因**: 重叠区域未正确去除

**解决方案**:
1. 检查质量报告中的"偏移异常"
2. 使用更高的重叠百分比（35%）
3. 启用视觉特征匹配策略

### 问题：拼接后出现断层

**原因**: 重叠不足或匹配失败

**解决方案**:
1. 检查质量报告中的"低置信度"
2. 降低滚动速度
3. 使用保守配置（`CaptureConfig.sensitive`）

### 问题：拼接速度慢

**原因**: 使用了高精度策略

**解决方案**:
1. 使用 MSE 策略（`forceStrategy: .mse`）
2. 增加搜索步长
3. 降低降采样宽度

## 最佳实践

### 1. 选择合适的重叠百分比

- **快速滚动**: 35% 重叠（更多重叠，更安全）
- **正常滚动**: 30% 重叠（推荐）
- **慢速滚动**: 25% 重叠（更快，但需要稳定）

### 2. 选择合适的策略

- **高质量需求**: 使用 `.vision` 策略
- **实时预览**: 使用 `.mse` 策略
- **简单内容**: 使用 `.fixed` 策略

### 3. 处理质量问题

- 严重问题（🔴）必须修复
- 中等问题（🟠）建议修复
- 轻微问题（🟡）可选修复

### 4. 使用视口追踪

- 在长图采集时保持视口指示器开启
- 定期检查当前位置
- 利用回滚建议快速定位问题

## 未来改进

- [ ] 集成 Vision 框架的特征匹配
- [ ] 支持水平拼接（宽图）
- [ ] 添加更多质量检测指标
- [ ] 降采样优化（GPU 加速）
- [ ] 批量处理支持
- [ ] 导出详细日志

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                  LongScreenshotFlowController                │
│                      (流程控制器)                             │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              IntelligentStitchingService                     │
│              (核心拼接服务 - actor)                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  1. 策略选择 (selectStrategy)                          │  │
│  │  2. 逐行匹配 (matchByStrips)                          │  │
│  │  3. 复杂度检测 (calculateComplexity)                  │  │
│  │  4. 置信度计算 (calculateConfidence)                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
    ┌─────────────┐ ┌────────────────┐ ┌────────────────┐
    │  Stitching  │ │   Viewport     │ │  Intelligent   │
    │  Quality    │ │   Tracker      │ │  Stitching     │
    │  Monitor    │ │   (主线程)     │ │  Models        │
    │  (actor)    │ │                │ │                │
    └─────────────┘ └────────────────┘ └────────────────┘
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可

MIT License
