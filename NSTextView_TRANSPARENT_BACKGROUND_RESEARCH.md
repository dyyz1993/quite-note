# NSTextView 透明背景文本输入 - 深度调研报告

## 目录
1. [核心概念](#核心概念)
2. [关键属性详解](#关键属性详解)
3. [NSViewRepresentable 实现模式](#nsviewrepresentable-实现模式)
4. [完整可运行代码](#完整可运行代码)
5. [常见问题和解决方案](#常见问题和解决方案)
6. [参考资源](#参考资源)

---

## 核心概念

### 透明背景实现的三层架构

```
SwiftUI View (NSViewRepresentable)
    ↓
Custom NSView (容器)
    ↓
NSScrollView → NSTextView (实际文本视图)
```

**关键点**: 透明背景需要在**三个层级**上都进行配置:
1. **NSScrollView**: `drawsBackground = false`
2. **NSTextView**: `drawsBackground = false` + `backgroundColor = .clear`
3. **NSView 容器**: 确保父视图不绘制背景

---

## 关键属性详解

### 1. NSTextView 配置

#### `drawsBackground` (最重要)
```swift
textView.drawsBackground = false  // ❌ 不绘制背景
```
- **默认值**: `true`
- **作用**: 控制 NSTextView 是否绘制背景色
- **设置 false**: 完全透明,显示父视图背景
- **设置 true**: 使用 `backgroundColor` 属性填充背景

#### `backgroundColor`
```swift
textView.backgroundColor = NSColor.clear  // 透明色
textView.backgroundColor = .textBackgroundColor  // 系统默认文本背景色
textView.backgroundColor = .windowBackgroundColor  // 窗口背景色
```
- **仅在 `drawsBackground = true` 时生效**
- **`.clear`**: 完全透明
- **系统颜色**: 根据深色/浅色模式自动调整

#### `isRichText`
```swift
textView.isRichText = false  // 纯文本模式
textView.isRichText = true   // 富文本模式
```
- **纯文本模式**: 更轻量,适合简单输入
- **富文本模式**: 支持格式化、图片、颜色等

### 2. NSScrollView 配置

#### `drawsBackground`
```swift
scrollView.drawsBackground = false  // ScrollView 透明
```
- **作用**: 控制 ScrollView 的 clip view 是否绘制背景
- **透明背景必设**: 否则会出现白色/灰色背景

#### 其他重要属性
```swift
scrollView.hasVerticalScroller = true
scrollView.borderType = .noBorder
scrollView.autoresizingMask = [.width, .height]
```

### 3. TextContainer 配置

```swift
let textContainer = NSTextContainer()
textContainer.widthTracksTextView = true  // 宽度跟随 TextView
textContainer.containerSize = NSSize(
    width: contentSize.width,
    height: CGFloat.greatestFiniteMagnitude  // 高度无限
)
```

---

## NSViewRepresentable 实现模式

### 标准模式结构

```swift
struct TransparentTextView: NSViewRepresentable {
    @Binding var text: String

    // 1. 创建 Coordinator (处理委托)
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // 2. 创建 NSView
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // 配置透明背景
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear

        // 其他配置...
        scrollView.documentView = textView

        return scrollView
    }

    // 3. 更新 NSView
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let textView = view.documentView as? NSTextView else { return }

        // 避免光标跳动:只在文本真正改变时更新
        guard textView.string != text else { return }
        textView.string = text
    }

    // 4. Coordinator 类
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TransparentTextView

        init(_ parent: TransparentTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
```

---

## 完整可运行代码

### 方案 1: 简化透明文本视图 (推荐用于简单场景)

```swift
import SwiftUI

struct TransparentTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var font: NSFont = .systemFont(ofSize: 14)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // 创建 ScrollView
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false  // 🔑 透明背景
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        // 创建 TextView
        let textView = NSTextView()
        textView.drawsBackground = false  // 🔑 透明背景
        textView.backgroundColor = .clear  // 🔑 透明色
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.font = font
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // 设置为 ScrollView 的文档视图
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let textView = view.documentView as? NSTextView else { return }

        // 避免重复更新导致光标跳动
        guard textView.string != text else { return }

        // 保存当前选中范围
        let selectedRange = textView.selectedRange()
        textView.string = text
        textView.selectedRange = selectedRange
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TransparentTextView

        init(_ parent: TransparentTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// 使用示例
struct ContentView: View {
    @State private var text = "在这里输入文本..."

    var body: some View {
        VStack {
            Text("透明背景文本编辑器")
                .font(.headline)

            ZStack {
                // 背景颜色 (测试透明效果)
                Color.blue.opacity(0.2)

                TransparentTextView(
                    text: $text,
                    isEditable: true,
                    font: .systemFont(ofSize: 16)
                )
            }
            .frame(height: 200)
            .cornerRadius(8)
        }
        .padding()
    }
}
```

### 方案 2: 完整功能版 (基于 MacEditorTextView)

```swift
import SwiftUI

struct AdvancedTransparentTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var font: NSFont? = .systemFont(ofSize: 14, weight: .regular)

    var onEditingChanged: () -> Void = {}
    var onCommit: () -> Void = {}
    var onTextChange: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CustomTextView {
        let textView = CustomTextView(
            text: text,
            isEditable: isEditable,
            font: font
        )
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ view: CustomTextView, context: Context) {
        view.text = text
        view.selectedRanges = context.coordinator.selectedRanges
    }
}

// MARK: - Coordinator
extension AdvancedTransparentTextView {
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AdvancedTransparentTextView
        var selectedRanges: [NSValue] = []

        init(_ parent: AdvancedTransparentTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEditingChanged()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            selectedRanges = textView.selectedRanges
            parent.onTextChange(parent.text)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onCommit()
        }
    }
}

// MARK: - CustomTextView
final class CustomTextView: NSView {
    private var isEditable: Bool
    private var font: NSFont?

    weak var delegate: NSTextViewDelegate?

    var text: String {
        didSet {
            textView.string = text
        }
    }

    var selectedRanges: [NSValue] = [] {
        didSet {
            guard selectedRanges.count > 0 else { return }
            textView.selectedRanges = selectedRanges
        }
    }

    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false  // 🔑 透明
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalRuler = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var textView: NSTextView = {
        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()

        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: scrollView.frame.size)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask = .width
        textView.backgroundColor = .clear  // 🔑 透明
        textView.delegate = self.delegate
        textView.drawsBackground = false  // 🔑 不绘制背景
        textView.font = self.font
        textView.isEditable = self.isEditable
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.textColor = .labelColor
        textView.allowsUndo = true

        return textView
    }()

    init(text: String, isEditable: Bool, font: NSFont?) {
        self.font = font
        self.isEditable = isEditable
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        setupScrollViewConstraints()
        setupTextView()
    }

    func setupScrollViewConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
    }

    func setupTextView() {
        scrollView.documentView = textView
    }
}

// 使用示例
struct AdvancedContentView: View {
    @State private var queryText = """
    {
      planets {
        name
      }
    }
    """

    @State private var statusText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdvancedTransparentTextView(
                text: $queryText,
                isEditable: true,
                font: .userFixedPitchFont(ofSize: 14)
            ) {
                statusText = "开始编辑"
            } onCommit: {
                statusText = "提交编辑"
            } onTextChange: { value in
                statusText = "文本变化: \(value.count) 字符"
            }
            .frame(
                minWidth: 300,
                maxWidth: .infinity,
                minHeight: 300,
                maxHeight: .infinity
            )

            Divider()

            Text(statusText)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .font(.caption)
        }
    }
}
```

### 方案 3: 最简透明版本 (适合快速原型)

```swift
struct MinimalTransparentTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) -> Void {
        guard let textView = view.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MinimalTransparentTextView

        init(_ parent: MinimalTransparentTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
```

---

## 常见问题和解决方案

### 问题 1: 背景仍然显示白色/灰色

**原因**: 只设置了 NSTextView 的 `drawsBackground`,但忘记设置 NSScrollView

**解决方案**:
```swift
scrollView.drawsBackground = false  // 必须设置
scrollView.contentView.drawsBackground = false  // 某些情况需要
```

### 问题 2: 光标跳动问题

**原因**: `updateNSView` 每次都重新设置文本,导致光标位置重置

**解决方案**:
```swift
func updateNSView(_ view: NSScrollView, context: Context) {
    guard let textView = view.documentView as? NSTextView else { return }

    // 方案 A: 检查文本是否真的改变
    guard textView.string != text else { return }
    textView.string = text

    // 方案 B: 保存和恢复选中范围
    let selectedRanges = textView.selectedRanges
    textView.string = text
    textView.selectedRanges = selectedRanges

    // 方案 C: 使用 Coordinator 存储选中状态
    textView.selectedRanges = context.coordinator.selectedRanges
}
```

### 问题 3: SwiftUI 绑定导致无限循环

**原因**: `textDidChange` 更新 `@Binding`,触发 SwiftUI 刷新,调用 `updateNSView`,又触发 `textDidChange`

**解决方案**:
```swift
// 方案 A: 在 updateNSView 中添加 guard
guard textView.string != text else { return }

// 方案 B: 使用防抖
private var debounceTimer: DispatchWorkItem?

func textDidChange(_ notification: Notification) {
    debounceTimer?.cancel()
    debounceTimer = DispatchWorkItem {
        parent.text = textView.string
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: debounceTimer!)
}
```

### 问题 4: 滚动时出现文字阴影

**原因**: NSWindow 和 NSTextView 都透明时,滚动可能导致渲染问题

**解决方案**:
```swift
// 方案 A: 设置 wantsLayer
textView.wantsLayer = true
textView.layer?.backgroundColor = .clear

// 方案 B: 使用半透明背景代替完全透明
textView.backgroundColor = NSColor.black.withAlphaComponent(0.01)
```

### 问题 5: 字体渲染模糊

**原因**: 透明背景时,需要正确的 layer 设置

**解决方案**:
```swift
textView.wantsLayer = true
textView.layer?.opacity = 1.0

// 或者
scrollView.wantsLayer = true
scrollView.layer?.backgroundColor = .clear
```

---

## 调试技巧

### 1. 验证透明效果

```swift
// 在 NSTextView 后面放置一个彩色视图
ZStack {
    Color.red.opacity(0.3)  // 应该能透过文本看到红色
    TransparentTextView(text: $text)
}
```

### 2. 检查视图层级

```swift
// 打印视图层级
print("ScrollView drawsBackground: \(scrollView.drawsBackground)")
print("TextView drawsBackground: \(textView.drawsBackground)")
print("TextView backgroundColor: \(textView.backgroundColor)")
```

### 3. 测试边界情况

```swift
// 测试 1: 空文本
TransparentTextView(text: .constant(""))

// 测试 2: 超长文本
TransparentTextView(text: .constant(String(repeating: "测试\n", count: 100)))

// 测试 3: 特殊字符
TransparentTextView(text: .constant("🎉 emoji \n\t 制表符"))
```

---

## 最佳实践

### 性能优化

```swift
// 1. 避免频繁更新
private var lastUpdateTime: Date?
func updateNSView(_ view: NSScrollView, context: Context) {
    let now = Date()
    guard let last = lastUpdateTime, now.timeIntervalSince(last) > 0.016 else { return } // 60fps
    lastUpdateTime = now
    // ...
}

// 2. 使用纯文本模式
textView.isRichText = false  // 性能更好

// 3. 禁用不必要的功能
textView.isAutomaticQuoteSubstitutionEnabled = false
textView.isAutomaticDashSubstitutionEnabled = false
```

### 可访问性

```swift
// 设置可访问性标签
textView.accessibilityLabel = "文本编辑器"
textView.accessibilityHint = "输入您的文本内容"

// 支持动态字体
textView.font = NSFont.preferredFont(forTextStyle: .body)
```

### 深色模式支持

```swift
// 使用系统颜色
textView.textColor = .labelColor
textView.insertionPointColor = .textColor
textView.selectedTextAttributes = [
    .backgroundColor: NSColor.selectedTextBackgroundColor
]
```

---

## 参考资源

### Apple 官方文档
- [NSTextView - Apple Developer](https://developer.apple.com/documentation/appkit/nstextview)
- [NSScrollView - Apple Developer](https://developer.apple.com/documentation/appkit/nsscrollview)
- [NSViewRepresentable - Apple Developer](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)

### 开源项目
- [MacEditorTextView Gist](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0) - 完整的 SwiftUI NSTextView 封装
- [STTextView](https://github.com/krzyzanowskim/STTextView) - 基于 TextKit 2 的高性能 TextView

### Stack Overflow 讨论
- [NSTextField transparent background](https://stackoverflow.com/questions/11120654/nstextfield-transparent-background)
- [Transparent NSCollectionView Background](https://stackoverflow.com/questions/42058337/transparent-nscollectionview-background)

### 社区资源
- [How to make TextView in SwiftUI for macOS #587](https://github.com/onmyway133/blog/issues/587)
- [How to customize NSTextView in AppKit #320](https://github.com/onmyway133/blog/issues/320)

---

## 总结

实现 NSTextView 透明背景的关键点:

1. **三层透明配置**: ScrollView + TextView + 背景色
2. **drawsBackground = false**: 最关键的属性
3. **backgroundColor = .clear**: 设置透明色
4. **避免光标跳动**: 在 `updateNSView` 中检查文本是否真的改变
5. **使用 Coordinator**: 正确处理 NSTextViewDelegate 事件
6. **性能考虑**: 对于大文本,使用防抖和增量更新

**推荐方案**:
- 简单场景: 方案 1 (简化透明文本视图)
- 复杂场景: 方案 2 (完整功能版)
- 快速原型: 方案 3 (最简透明版本)
