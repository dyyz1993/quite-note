# 快速开始 - 拼接算法测试框架

## 5 分钟快速上手

### 步骤 1：采集测试数据

使用现有的长截图功能采集一次滚动截图：

```swift
// 在代码中启动长截图
LongScreenshotFlowController.startIndependently(
    selection: selectionRect,
    targetScreen: screen
) { result in
    // 处理结果
}
```

或者手动滚动采集一组长截图帧。

### 步骤 2：保存为测试集

```swift
// 采集完成后，保存为测试集
try await LongScreenshotFlowController.shared.saveCurrentSessionAsTestSet(
    name: "测试集1",
    scenario: .webpage,  // 选择场景类型
    notes: "用于测试网页滚动拼接"
)
```

**可选的场景类型：**
- `.webpage` - 网页
- `.appUI` - App界面
- `.image` - 图片
- `.solidColor` - 纯色
- `.text` - 文本
- `.mixed` - 混合内容

### 步骤 3：运行算法对比

```swift
// 运行完整算法对比测试
await LongScreenshotFlowController.shared.runAlgorithmComparison()
```

测试会自动对比三种算法：
1. **Vision 框架** - 系统自带，速度快，精度高
2. **MSE 模板匹配** - 自定义算法，可调优
3. **固定重叠** - 简单对照，速度最快

### 步骤 4：查看报告

测试完成后，会自动弹出提示框，点击"查看报告"即可在浏览器中打开 HTML 报告。

报告包含：
- 📊 性能对比表格（处理时间、画布尺寸、置信度）
- 🖼️ 结果图片对比（每个算法的拼接结果）
- 📈 详细性能指标

## 高级用法

### 使用已有测试集

```swift
// 列出所有测试集
let testSets = await LongScreenshotFlowController.shared.listAllTestSets()

// 选择一个测试集运行对比
await LongScreenshotFlowController.shared.runComparisonOnTestSet(
    testSetId: testSets.first!.id
)
```

### 读取测试结果

```swift
let frames = await TestDataSetManager.shared.loadTemporaryFrames()
let report = await StitchingBenchmark.shared.runFullBenchmark(
    frames: frames,
    captureOverlap: 0.10
)

// 访问每个算法的结果
for result in report.results {
    print("算法: \(result.algorithmName)")
    print("耗时: \(result.formattedTime)")
    print("置信度: \(result.formattedConfidence)")
    print("画布: \(result.formattedSize)")
}
```

## 性能指标解读

### 处理时间
- **Vision**: 10-50ms ⚡️ 最快
- **MSE**: 50-200ms 🔸 适中
- **固定**: <10ms ⚡️ 极快

### 平均置信度
- **Vision**: 90%+ ✅ 最高
- **MSE**: 60-80% ✅ 良好
- **固定**: 50% 🔸 基准

### 适用场景
- **Vision**: 所有场景，尤其是需要高精度
- **MSE**: 需要精细调整的场景
- **固定**: 快速预览、性能测试

## 故障排查

### 没有可用的测试帧

**问题**：运行测试时提示"没有可用的测试帧"

**解决方案**：
1. 先完成一次长截图采集
2. 确保采集成功（看到预览图）
3. 然后再运行测试

### 测试失败

**问题**：测试过程中出现错误

**解决方案**：
1. 检查日志输出
2. 确保测试集文件完整
3. 尝试重新采集测试数据

### 报告无法打开

**问题**：生成报告后无法在浏览器中打开

**解决方案**：
1. 手动打开报告文件（路径在日志中）
2. 报告保存在 `/tmp/QuiteNote/BenchmarkReports/`
3. 直接用浏览器打开 HTML 文件

## 示例代码

### 完整的工作流程示例

```swift
// 1. 启动长截图采集
LongScreenshotFlowController.startIndependently(
    selection: selectionRect,
    targetScreen: NSScreen.main!
) { result in
    switch result {
    case .success(let image):
        print("采集成功，图片尺寸: \(image.size)")

        // 2. 保存为测试集
        Task {
            try await LongScreenshotFlowController.shared.saveCurrentSessionAsTestSet(
                name: "我的第一次测试",
                scenario: .webpage,
                notes: "测试 Vision vs MSE"
            )

            // 3. 运行算法对比
            await LongScreenshotFlowController.shared.runAlgorithmComparison()
        }

    case .failure(let error):
        print("采集失败: \(error.localizedDescription)")
    }
}
```

### 批量测试多个场景

```swift
let scenarios: [TestScenario] = [.webpage, .appUI, .text, .mixed]

for scenario in scenarios {
    // 采集该场景的测试数据
    // ...

    // 保存测试集
    try await LongScreenshotFlowController.shared.saveCurrentSessionAsTestSet(
        name: "\(scenario.description)测试",
        scenario: scenario,
        notes: "批量测试"
    )

    // 运行对比
    await LongScreenshotFlowController.shared.runAlgorithmComparison()
}
```

## 下一步

- 📖 阅读完整文档：`Sources/QuiteNote/UI/ScreenshotV2/LongScreenshot/Testing/README.md`
- 🔧 查看实现细节：`Testing/` 目录下的 Swift 文件
- 📊 查看总结报告：`TESTING_FRAMEWORK_SUMMARY.md`
