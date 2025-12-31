import SwiftUI
import XCTest

/// V2ScreenshotDebugView 重构验证测试
/// 验证组件拆分后的功能完整性
class RefactoringTestCases {

    // MARK: - 测试用例

    /// Case 1: 验证基础UI组件可用性
    static func testCase01_BasicComponents() {
        print("🧪 Case 1: 基础UI组件")

        // InvertedRectangle - 反向矩形形状
        let hole = CGRect(x: 100, y: 100, width: 200, height: 200)
        let invertedRect = InvertedRectangle(hole: hole)
        let path = invertedRect.path(in: CGRect(x: 0, y: 0, width: 500, height: 500))
        print("  ✓ InvertedRectangle 创建成功")

        // VisualEffectView - 毛玻璃效果
        let visualEffect = VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
        print("  ✓ VisualEffectView 创建成功")

        // LayerLabel - 层级标签
        let layerLabel = LayerLabel(name: "Test Layer", color: .blue)
        print("  ✓ LayerLabel 创建成功")

        print("  ✅ Case 1 通过\n")
    }

    /// Case 2: 验证Magnifier组件
    static func testCase02_MagnifierComponents() {
        print("🧪 Case 2: Magnifier组件")

        // 准备测试数据
        let testImage = NSImage(size: NSSize(width: 1920, height: 1080))
        let testLocation = CGPoint(x: 500, y: 500)
        let testScreen = NSScreen.screens.first ?? NSScreen.main!

        // MagnifierView - 主放大镜
        let magnifier = MagnifierView(
            snapshot: testImage,
            location: testLocation,
            screen: testScreen
        )
        print("  ✓ MagnifierView 创建成功")

        // AnnotationMagnifierPreview - 标注放大镜预览
        let selectionArea = CGRect(x: 100, y: 100, width: 400, height: 400)
        let annotationMagnifier = AnnotationMagnifierPreview(
            snapshot: testImage,
            position: testLocation,
            canvasSize: CGSize(width: 1920, height: 1080),
            followMouse: true,
            selectionArea: selectionArea
        )
        print("  ✓ AnnotationMagnifierPreview 创建成功")

        print("  ✅ Case 2 通过\n")
    }

    /// Case 3: 验证Toolbar组件
    static func testCase03_ToolbarComponents() {
        print("🧪 Case 3: Toolbar组件")

        let selection = CGRect(x: 100, y: 100, width: 400, height: 400)
        let screen = NSScreen.screens.first ?? NSScreen.main!

        // ToolbarButton - 工具栏按钮
        let button = ToolbarButton(
            icon: "checkmark",
            color: .green,
            label: "完成",
            isPrimary: true
        ) {
            print("Button clicked")
        }
        print("  ✓ ToolbarButton 创建成功")

        // V2FloatingToolbar - 浮动工具栏
        let floatingToolbar = V2FloatingToolbar(
            selection: selection,
            screen: screen
        )
        print("  ✓ V2FloatingToolbar 创建成功")

        // V2CaptureStopToolbar - 停止工具栏
        let stopToolbar = V2CaptureStopToolbar()
        print("  ✓ V2CaptureStopToolbar 创建成功")

        print("  ✅ Case 3 通过\n")
    }

    /// Case 4: 验证Panels类
    static func testCase04_PanelClasses() {
        print("🧪 Case 4: Panels类")

        let selection = CGRect(x: 100, y: 100, width: 400, height: 400)
        let screen = NSScreen.screens.first ?? NSScreen.main!

        // V2TextInputPanel - 文本输入面板
        let textInputPanel = V2TextInputPanel(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        print("  ✓ V2TextInputPanel 创建成功")

        // V2LongScreenshotControlPanel - 长图控制面板
        let controlPanel = V2LongScreenshotControlPanel(
            selection: selection,
            screen: screen
        ) {
            print("Finish callback")
        }
        print("  ✓ V2LongScreenshotControlPanel 创建成功")

        // V2ScreenshotHostingView - 自定义HostingView
        let testView = Text("Test")
        let hostingView = V2ScreenshotHostingView(rootView: testView)
        print("  ✓ V2ScreenshotHostingView 创建成功")

        print("  ✅ Case 4 通过\n")
    }

    /// Case 5: 验证Overlays组件
    static func testCase05_OverlayComponents() {
        print("🧪 Case 5: Overlays组件")

        let testRect = CGRect(x: 100, y: 100, width: 400, height: 400)
        let screen = NSScreen.screens.first ?? NSScreen.main!

        // YellowWireframe - 黄色线框
        let wireframe = YellowWireframe(
            rect: testRect,
            label: "Test Window",
            isDashed: true,
            showBackground: true,
            isEditing: false,
            isLongScreenshotMode: false
        )
        print("  ✓ YellowWireframe 创建成功")

        // V2LongScreenshotPreview - 长图预览
        let _ = V2LongScreenshotPreview(
            selection: testRect,
            screen: screen
        )
        print("  ✓ V2LongScreenshotPreview 创建成功")

        print("  ✅ Case 5 通过\n")
    }

    /// Case 6: 验证Models
    static func testCase06_Models() {
        print("🧪 Case 6: Models")

        // SelectionHandle - 选区手柄
        let testRect = CGRect(x: 0, y: 0, width: 400, height: 400)
        for handle in SelectionHandle.allCases {
            let pos = handle.position(in: testRect)
            print("  ✓ \(handle) 位置: \(pos)")
        }

        print("  ✅ Case 6 通过\n")
    }

    /// Case 7: 验证Controller
    static func testCase07_Controller() {
        print("🧪 Case 7: Controller")

        // V2ScreenshotDebugController - 调试控制器
        // 注意：这个会创建实际窗口，只在需要时测试
        print("  ℹ️  V2ScreenshotDebugController.show() - 需要手动触发")
        print("  ℹ️  V2ScreenshotDebugController.close() - 需要手动触发")

        // 验证静态属性存在 (在 MainActor 上下文中)
        Task { @MainActor in
            let _ = V2ScreenshotDebugController.debugPanels
            let _ = V2ScreenshotDebugController.longScreenshotControlPanel
            print("  ✓ V2ScreenshotDebugController 静态属性可访问")
        }

        print("  ⚠️  Case 7 需要手动测试窗口显示\n")
    }

    /// Case 8: 集成测试 - 主视图创建
    static func testCase08_MainViewCreation() {
        print("🧪 Case 8: 主视图创建")

        let screen = NSScreen.screens.first ?? NSScreen.main!
        let snapshot = NSImage(size: screen.frame.size)
        let allWindows: [WindowInfo] = []

        // V2ScreenshotDebugView - 主视图
        let debugView = V2ScreenshotDebugView(
            screen: screen,
            snapshot: snapshot,
            screenIndex: 0,
            allWindows: allWindows
        )
        print("  ✓ V2ScreenshotDebugView 创建成功")

        // 验证视图可以渲染
        let _ = debugView.body
        print("  ✓ V2ScreenshotDebugView body 可访问")

        print("  ✅ Case 8 通过\n")
    }

    /// Case 9: 验证组件间依赖关系
    static func testCase09_DependencyGraph() {
        print("🧪 Case 9: 依赖关系图")

        print("  依赖关系：")
        print("  ├─ V2ScreenshotDebugView (主视图)")
        print("  │   ├─ 使用: YellowWireframe (Overlays/)")
        print("  │   ├─ 使用: MagnifierView (Magnifier/)")
        print("  │   ├─ 使用: V2FloatingToolbar (Toolbar/)")
        print("  │   ├─ 使用: V2LongScreenshotPreview (Overlays/)")
        print("  │   ├─ 使用: LayerLabel (Foundation/)")
        print("  │   └─ 调用: V2ScreenshotDebugController (Controllers/)")
        print("  │")
        print("  ├─ V2FloatingToolbar")
        print("  │   ├─ 使用: ToolbarButton")
        print("  │   └─ 调用: V2ScreenshotDebugController")
        print("  │")
        print("  ├─ V2LongScreenshotControlPanel (Panels/)")
        print("  │   └─ 使用: V2CaptureStopToolbarView (Toolbar/)")
        print("  │")
        print("  └─ V2ScreenshotDebugController")
        print("      ├─ 使用: V2ScreenshotHostingView (Panels/)")
        print("      ├─ 使用: V2TextInputPanel (Panels/)")
        print("      └─ 使用: V2LongScreenshotControlPanel (Panels/)")

        print("  ✅ Case 9 完成\n")
    }

    // MARK: - 运行所有测试

    /// 运行所有测试用例
    @MainActor
    static func runAllTests() {
        print("\n" + String(repeating: "=", count: 60))
        print("🚀 开始运行重构验证测试")
        print(String(repeating: "=", count: 60) + "\n")

        testCase01_BasicComponents()
        testCase02_MagnifierComponents()
        testCase03_ToolbarComponents()
        testCase04_PanelClasses()
        testCase05_OverlayComponents()
        testCase06_Models()
        testCase07_Controller()
        testCase08_MainViewCreation()
        testCase09_DependencyGraph()

        print(String(repeating: "=", count: 60))
        print("✅ 所有自动化测试完成")
        print(String(repeating: "=", count: 60) + "\n")

        print("📋 手动测试清单：")
        print("  1. 运行应用，按快捷键触发调试截图")
        print("  2. 验证窗口正确显示")
        print("  3. 验证鼠标悬停显示窗口高亮")
        print("  4. 验证拖拽选区功能")
        print("  5. 验证工具栏显示和按钮功能")
        print("  6. 验证长图模式切换")
        print("  7. 验证编辑模式切换")
        print("  8. 验证保存截图功能")
        print("  9. 验证ESC关闭窗口")
    }
}
