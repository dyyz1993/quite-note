# QuiteNote 项目架构重新设计方案

> 版本：2.0
> 日期：2025-12-09
> 作者：Claude Code

## 目录

1. [架构概览](#1-架构概览)
2. [组件架构设计](#2-组件架构设计)
3. [功能模块分块](#3-功能模块分块)
4. [分层架构](#4-分层架构)
5. [数据流设计](#5-数据流设计)
6. [依赖管理](#6-依赖管理)
7. [项目文件结构](#7-项目文件结构)
8. [设计模式应用](#8-设计模式应用)
9. [扩展性考虑](#9-扩展性考虑)
10. [性能优化策略](#10-性能优化策略)

---

## 1. 架构概览

### 1.1 架构原则

- **模块化**：高内聚、低耦合
- **可测试性**：依赖注入、协议优先
- **可扩展性**：插件化架构
- **一致性**：统一的设计语言和交互模式
- **性能优先**：优化渲染和数据处理

### 1.2 架构图

```
┌─────────────────────────────────────────────────────────┐
│                    表现层 (Presentation)                  │
├─────────────────────────────────────────────────────────┤
│  UI Views (SwiftUI) │ Components │ Theme │ Animation   │
├─────────────────────────────────────────────────────────┤
│                    业务层 (Business)                      │
├─────────────────────────────────────────────────────────┤
│  Services │ Managers │ ViewModels │ State Management   │
├─────────────────────────────────────────────────────────┤
│                    数据层 (Data)                          │
├─────────────────────────────────────────────────────────┤
│  Repositories │ Core Data │ Bluetooth │ Keychain       │
├─────────────────────────────────────────────────────────┤
│                   基础设施层 (Infrastructure)             │
├─────────────────────────────────────────────────────────┤
│  Utils │ Extensions │ Helpers │ Platform Abstraction   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. 组件架构设计

### 2.1 组件分类体系

#### 2.1.1 按层级分类

**基础组件 (Foundation Components)**
- 最底层的 UI 组件
- 不依赖业务逻辑
- 高度可复用

```
UI/
├── Foundation/
│   ├── Buttons/
│   ├── Inputs/
│   ├── Typography/
│   ├── Layouts/
│   └── Icons/
```

**业务组件 (Business Components)**
- 封装特定业务逻辑
- 依赖基础组件
- 中等复用性

```
UI/
├── Business/
│   ├── Records/
│   ├── Settings/
│   ├── Bluetooth/
│   └── AI/
```

**复合组件 (Composite Components)**
- 组合多个业务组件
- 实现复杂功能
- 低复用性

```
UI/
├── Composite/
│   ├── FloatingPanel/
│   ├── SettingsPanel/
│   └── Dashboard/
```

#### 2.1.2 按功能分类

**交互组件**
- Button, Toggle, Slider, TextField
- 统一的交互反馈

**展示组件**
- Card, List, Grid, Badge
- 统一的视觉样式

**布局组件**
- Container, Grid, Stack, Panel
- 响应式布局支持

**反馈组件**
- Toast, Modal, Dialog, Loading
- 统一的动效和样式

### 2.2 组件设计原则

#### 2.2.1 SOLID 原则

**单一职责原则 (SRP)**
```swift
// ✅ 正确：每个组件职责单一
struct PrimaryButton: View {
    // 只负责 primary 按钮的样式和交互
}

struct SecondaryButton: View {
    // 只负责 secondary 按钮的样式和交互
}

// ❌ 错误：一个组件承担多种职责
struct Button: View {
    enum Style { case primary, secondary, danger }
    // 混合了多种按钮样式的逻辑
}
```

**开放封闭原则 (OCP)**
```swift
// ✅ 正确：通过协议扩展
protocol Themeable {
    var theme: Theme { get }
}

extension Themeable where Self: View {
    func applyTheme() -> some View {
        // 默认主题应用逻辑
    }
}

// 组件可以扩展此协议
struct CustomButton: View, Themeable {
    var theme: Theme
    // 继承默认行为，可选择性重写
}
```

**依赖倒置原则 (DIP)**
```swift
// ✅ 正确：依赖抽象而非具体实现
protocol RecordService {
    func getRecords() -> [Record]
    func addRecord(_ record: Record)
}

struct RecordListView: View {
    @StateObject private var viewModel: RecordListViewModel

    init(service: RecordService) {
        _viewModel = StateObject(wrappedValue: RecordListViewModel(service: service))
    }
}
```

#### 2.2.2 组件接口设计

**Props 设计原则**
```swift
struct ThemedButton<Label: View>: View {
    // 1. 必需参数
    let action: () -> Void

    // 2. 可选参数（带默认值）
    let style: ButtonStyle = .primary
    let size: ButtonSize = .medium
    let disabled: Bool = false

    // 3. 内容块
    @ViewBuilder let label: () -> Label

    // 4. 回调（可选）
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(ThemeButtonStyle(style: style, size: size, disabled: disabled))
    }
}

// 使用示例
ThemedButton(style: .primary, size: .large, action: {
    print("clicked")
}) {
    Text("Click me")
}
```

**事件处理**
```swift
protocol ComponentEvents {
    func onAppear()
    func onDisappear()
    func onHoverChanged(_ hovering: Bool)
    func onFocusChanged(_ focused: Bool)
}

struct InteractiveCard: View, ComponentEvents {
    @State private var isHovering = false

    var body: some View {
        CardView()
            .onHover { hovering in
                isHovering = hovering
                onHoverChanged(hovering)
            }
            .onAppear {
                onAppear()
            }
    }

    func onAppear() { /* 默认实现 */ }
    func onDisappear() { /* 默认实现 */ }
    func onHoverChanged(_ hovering: Bool) { /* 默认实现 */ }
    func onFocusChanged(_ focused: Bool) { /* 默认实现 */ }
}
```

---

## 3. 功能模块分块

### 3.1 核心模块

#### 3.1.1 数据管理模块 (Data Management)

**职责**
- 记录的增删改查
- 数据持久化
- 数据同步和备份
- 搜索和过滤

**文件结构**
```
Sources/QuiteNote/Data/
├── Models/
│   ├── Record.swift
│   ├── Preferences.swift
│   └── Device.swift
├── Repositories/
│   ├── RecordRepository.swift
│   ├── PreferenceRepository.swift
│   └── DeviceRepository.swift
├── Persistence/
│   ├── CoreData/
│   │   ├── CoreDataStack.swift
│   │   ├── CDRecord.swift
│   │   └── Migrations/
│   └── Cache/
│       ├── RecordCache.swift
│       └── ImageCache.swift
├── Services/
│   ├── SearchService.swift
│   ├── ExportService.swift
│   └── BackupService.swift
└── Extensions/
    ├── Record+Extensions.swift
    └── Date+Extensions.swift
```

**核心接口**
```swift
protocol RecordRepository {
    func getAllRecords() async -> [Record]
    func getRecords(query: SearchQuery) async -> [Record]
    func addRecord(_ record: Record) async throws
    func updateRecord(_ record: Record) async throws
    func deleteRecord(_ id: UUID) async throws
    func deleteAllRecords() async throws
    func exportRecords(format: ExportFormat) async throws -> URL
}

protocol SearchService {
    func search(query: String, options: SearchOptions) -> [Record]
    func getIndexStats() -> IndexStats
    func rebuildIndex() async
}
```

#### 3.1.2 设备连接模块 (Device Connectivity)

**职责**
- Bluetooth 设备管理
- 硬件按钮事件处理
- 设备状态监控
- 连接配置

**文件结构**
```
Sources/QuiteNote/Device/
├── Models/
│   └── Device.swift
├── Services/
│   ├── BluetoothManager.swift
│   ├── DeviceDiscoveryService.swift
│   └── DeviceConfigurationService.swift
├── Protocols/
│   ├── DeviceProtocol.swift
│   └── ButtonEventProtocol.swift
└── Utils/
    ├── UUIDManager.swift
    └── RSSICalculator.swift
```

**核心接口**
```swift
protocol DeviceManager {
    var devices: [Device] { get }
    var connectedDevice: Device? { get }

    func startScanning()
    func stopScanning()
    func connect(to device: Device) async throws
    func disconnect(from device: Device) async throws
    func sendCommand(_ command: DeviceCommand) async throws
}

protocol ButtonEventDelegate {
    func onButtonPressed(buttonId: String, eventType: ButtonEventType)
    func onDeviceConnected(_ device: Device)
    func onDeviceDisconnected(_ device: Device)
}
```

#### 3.1.3 AI 服务模块 (AI Services)

**职责**
- AI 提炼服务管理
- 本地规则引擎
- 云端 API 集成
- 结果处理和展示

**文件结构**
```
Sources/QuiteNote/AI/
├── Models/
│   ├── AIResult.swift
│   ├── AIProvider.swift
│   └── AIConfiguration.swift
├── Providers/
│   ├── LocalAIService.swift
│   ├── OpenAIService.swift
│   ├── AnthropicService.swift
│   └── AzureAIService.swift
├── Engines/
│   ├── RuleBasedEngine.swift
│   └── MLBasedEngine.swift
├── Utils/
│   ├── TextProcessor.swift
│   ├── ResultValidator.swift
│   └── AICacheManager.swift
└── Extensions/
    ├── String+AIPreprocessing.swift
    └── Dictionary+AIExtensions.swift
```

**核心接口**
```swift
protocol AIService {
    var provider: AIProvider { get }
    var isAvailable: Bool { get }

    func summarize(text: String, options: AISummaryOptions) async throws -> AIResult
    func extractKeywords(text: String, limit: Int) async throws -> [String]
    func classify(text: String, categories: [String]) async throws -> String
    func testConnection() async throws -> Bool
}

protocol AIProvider {
    var name: String { get }
    var baseURL: URL { get }
    var requiresAPIKey: Bool { get }

    func buildRequest(for prompt: String, options: AIOptions) -> URLRequest
    func parseResponse(_ data: Data) -> Result<AIResult, AIErrors>
}
```

#### 3.1.4 用户界面模块 (User Interface)

**职责**
- UI 组件库
- 主题系统
- 动画系统
- 布局管理

**文件结构**
```
Sources/QuiteNote/UI/
├── Theme/
│   ├── Color+Theme.swift
│   ├── Font+Theme.swift
│   ├── Spacing+Theme.swift
│   ├── Shape+Theme.swift
│   ├── Animation+Theme.swift
│   └── ThemeManager.swift
├── Components/
│   ├── Foundation/
│   │   ├── Buttons/
│   │   ├── Inputs/
│   │   ├── Typography/
│   │   └── Layouts/
│   ├── Business/
│   │   ├── Records/
│   │   ├── Settings/
│   │   ├── Bluetooth/
│   │   └── AI/
│   └── Composite/
│       ├── Panels/
│       ├── Overlays/
│       └── Navigation/
├── Views/
│   ├── Main/
│   │   ├── FloatingPanelView.swift
│   │   ├── SettingsView.swift
│   │   └── DashboardView.swift
│   └── Modals/
│       ├── ToastView.swift
│       ├── DialogView.swift
│       └── LoadingView.swift
├── ViewModels/
│   ├── MainViewModel.swift
│   ├── SettingsViewModel.swift
│   └── RecordListViewModel.swift
└── Extensions/
    ├── View+Theming.swift
    ├── View+Animations.swift
    └── View+Layout.swift
```

#### 3.1.5 系统集成模块 (System Integration)

**职责**
- 状态栏集成
- 快捷键管理
- 剪贴板监控
- 通知系统

**文件结构**
```
Sources/QuiteNote/System/
├── Services/
│   ├── StatusBarService.swift
│   ├── KeyboardShortcutService.swift
│   ├── ClipboardService.swift
│   └── NotificationService.swift
├── Integrations/
│   ├── NSStatusBar+Integration.swift
│   ├── NSEvent+Integration.swift
│   ├── NSPasteboard+Integration.swift
│   └── NSUserNotificationCenter+Integration.swift
└── Utils/
    ├── SystemInfo.swift
    └── PermissionChecker.swift
```

### 3.2 支撑模块

#### 3.2.1 安全模块 (Security)

**职责**
- Keychain 管理
- API 密钥安全
- 数据加密
- 权限验证

**文件结构**
```
Sources/QuiteNote/Security/
├── Keychain/
│   ├── KeychainManager.swift
│   ├── KeychainItem.swift
│   └── KeychainError.swift
├── Encryption/
│   ├── AESEncryption.swift
│   ├── HashGenerator.swift
│   └── SecureStorage.swift
└── Authentication/
    ├── APIKeyManager.swift
    └── PermissionManager.swift
```

#### 3.2.2 工具模块 (Utilities)

**职责**
- 通用工具函数
- 扩展方法
- 帮助类
- 调试工具

**文件结构**
```
Sources/QuiteNote/Utils/
├── Extensions/
│   ├── String+Extensions.swift
│   ├── Date+Extensions.swift
│   ├── Array+Extensions.swift
│   └── Dictionary+Extensions.swift
├── Helpers/
│   ├── Logger.swift
│   ├── Validator.swift
│   ├── Formatter.swift
│   └── Debouncer.swift
├── Utils/
│   ├── FileUtil.swift
│   ├── NetworkUtil.swift
│   └── PerformanceUtil.swift
└── Debug/
    ├── DebugMenu.swift
    ├── PerformanceMonitor.swift
    └── MockDataGenerator.swift
```

#### 3.2.3 配置模块 (Configuration)

**职责**
- 应用配置管理
- 环境变量
- 特性开关
- 默认值管理

**文件结构**
```
Sources/QuiteNote/Config/
├── Environment/
│   ├── EnvironmentType.swift
│   ├── EnvironmentConfig.swift
│   └── FeatureFlags.swift
├── Settings/
│   ├── AppSettings.swift
│   ├── UserPreferences.swift
│   └── SettingsManager.swift
└── Constants/
    ├── AppConstants.swift
    ├── APIConstants.swift
    └── UIConstants.swift
```

---

## 4. 分层架构

### 4.1 分层设计

#### 4.1.1 表现层 (Presentation Layer)

**职责**
- 用户界面展示
- 用户交互处理
- 视图状态管理

**组件**
- SwiftUI Views
- ViewModels
- Theme System
- Animation System

**依赖**
- Business Layer
- Theme System

```swift
// 示例：表现层组件
class MainViewModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let recordService: RecordService
    private let aiService: AIService

    init(recordService: RecordService, aiService: AIService) {
        self.recordService = recordService
        self.aiService = aiService
    }

    @MainActor
    func loadRecords() async {
        isLoading = true
        defer { isLoading = false }

        do {
            records = try await recordService.getAllRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

#### 4.1.2 业务层 (Business Layer)

**职责**
- 业务逻辑处理
- 服务协调
- 状态管理
- 业务规则验证

**组件**
- Services
- Managers
- Business Logic
- State Machines

**依赖**
- Data Layer
- Infrastructure Layer

```swift
// 示例：业务层服务
class RecordService {
    private let repository: RecordRepository
    private let aiService: AIService
    private let searchService: SearchService

    init(repository: RecordRepository,
         aiService: AIService,
         searchService: SearchService) {
        self.repository = repository
        self.aiService = aiService
        self.searchService = searchService
    }

    func processNewRecord(_ content: String) async throws -> Record {
        // 1. 检查重复
        if await repository.isDuplicate(content) {
            return try await repository.updateExistingRecord(content)
        }

        // 2. 创建新记录
        let record = Record(content: content)

        // 3. AI 处理（如果启用）
        if SettingsManager.shared.enableAIProcessing {
            let summary = try await aiService.summarize(text: content)
            record.aiSummary = summary
            record.isAIProcessed = true
        }

        // 4. 保存
        return try await repository.save(record)
    }
}
```

#### 4.1.3 数据层 (Data Layer)

**职责**
- 数据持久化
- 数据访问
- 数据同步
- 缓存管理

**组件**
- Repositories
- Data Access Objects
- Persistence Managers
- Cache Managers

**依赖**
- Platform APIs (CoreData, Keychain, etc.)

```swift
// 示例：数据层 Repository
class CoreDataRecordRepository: RecordRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func save(_ record: Record) async throws -> Record {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let cdRecord = CDRecord(context: self.context)
                    cdRecord.id = record.id
                    cdRecord.content = record.content
                    cdRecord.timestamp = record.timestamp

                    try self.context.save()

                    continuation.resume(returning: record)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

#### 4.1.4 基础设施层 (Infrastructure Layer)

**职责**
- 平台抽象
- 外部服务集成
- 工具函数
- 系统服务

**组件**
- Platform Abstractions
- External Service Clients
- Utility Classes
- System Integrations

```swift
// 示例：基础设施层抽象
protocol PlatformService {
    func getSystemInfo() -> SystemInfo
    func checkPermission(_ permission: Permission) async -> PermissionStatus
    func openURL(_ url: URL) -> Bool
}

class MacOSPlatformService: PlatformService {
    func getSystemInfo() -> SystemInfo {
        return SystemInfo(
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
        )
    }
}
```

### 4.2 层间通信

#### 4.2.1 依赖注入

```swift
// 使用依赖注入容器
class DIContainer {
    static let shared = DIContainer()

    private init() {}

    func resolve<T>() -> T {
        // 实现依赖解析逻辑
    }
}

// 在 App 中配置依赖
@main
struct QuiteNoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(DIContainer.shared.resolve() as MainViewModel)
        }
    }
}
```

#### 4.2.2 事件总线

```swift
protocol EventBus {
    func publish<T: Event>(_ event: T)
    func subscribe<T: Event>(_ type: T.Type, handler: @escaping (T) -> Void)
    func unsubscribe<T: Event>(_ type: T.Type)
}

class EventBusImpl: EventBus {
    private var handlers: [String: [AnyHandler]] = [:]

    func publish<T: Event>(_ event: T) {
        let key = String(describing: T.self)
        handlers[key]?.forEach { $0.handle(event) }
    }

    func subscribe<T: Event>(_ type: T.Type, handler: @escaping (T) -> Void) {
        let key = String(describing: T.self)
        if handlers[key] == nil {
            handlers[key] = []
        }
        handlers[key]?.append(AnyHandler(handler: handler))
    }
}
```

---

## 5. 数据流设计

### 5.1 单向数据流

```
User Action → View → ViewModel → Service → Repository → Database
                     ↑                                   ↓
                     └──── State Update ←─────── Data Fetch
```

### 5.2 状态管理

#### 5.2.1 全局状态

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var currentView: ViewType = .dashboard
    @Published var userPreferences: UserPreferences
    @Published var connectivityStatus: ConnectivityStatus = .connected
    @Published var notifications: [Notification] = []

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.userPreferences = UserPreferences.load(from: userDefaults)
    }

    func updatePreferences(_ updates: (inout UserPreferences) -> Void) {
        updates(&userPreferences)
        userPreferences.save(to: userDefaults)
        objectWillChange.send()
    }
}
```

#### 5.2.2 局部状态

```swift
@MainActor
final class RecordListViewModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var filter: RecordFilter = .all
    @Published var sortBy: SortOption = .date
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let recordService: RecordService

    init(recordService: RecordService) {
        self.recordService = recordService
    }

    @MainActor
    func loadRecords() async {
        isLoading = true
        errorMessage = nil

        do {
            records = try await recordService.getRecords(
                filter: filter,
                sortBy: sortBy
            )
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }
}
```

### 5.3 数据同步

#### 5.3.1 本地优先

```swift
protocol DataSyncManager {
    func syncLocalChanges() async throws
    func syncRemoteChanges() async throws
    func handleConflict(_ conflict: Conflict) async -> Resolution
}

class CoreDataSyncManager: DataSyncManager {
    private let cloudKitSync: CloudKitSyncService

    init(cloudKitSync: CloudKitSyncService) {
        self.cloudKitSync = cloudKitSync
    }

    func syncLocalChanges() async throws {
        // 1. 获取本地变更
        let changes = try await getLocalChanges()

        // 2. 推送到云端
        try await cloudKitSync.pushChanges(changes)

        // 3. 标记同步完成
        await markSynced(changes)
    }
}
```

---

## 6. 依赖管理

### 6.1 Swift Package Manager

**Package.swift**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuiteNote",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "QuiteNote",
            targets: ["QuiteNote"]
        ),
    ],
    dependencies: [
        // UI 和动画
        .package(url: "https://github.com/airbnb/lottie-ios.git", .upToNextMajor(from: "4.4.0")),

        // 网络请求
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.8.1")),

        // JSON 解析
        .package(url: "https://github.com/tristanhimmelman/ObjectMapper.git", .upToNextMajor(from: "4.2.0")),

        // 日志
        .package(url: "https://github.com/Logging/Logging.git", .upToNextMajor(from: "1.4.0")),

        // 测试
        .package(url: "https://github.com/Quick/Quick.git", .upToNextMajor(from: "6.1.0")),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", .upToNextMajor(from: "0.51.10")),
    ],
    targets: [
        .target(
            name: "QuiteNote",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "ObjectMapper", package: "ObjectMapper"),
                .product(name: "Logging", package: "Logging"),
            ],
            path: "Sources/QuiteNote",
            exclude: ["Tests"]
        ),
        .testTarget(
            name: "QuiteNoteTests",
            dependencies: [
                "QuiteNote",
                .product(name: "Quick", package: "Quick"),
                .product(name: "NSpec", package: "Quick"),
            ],
            path: "Tests/QuiteNoteTests"
        )
    ]
)
```

### 6.2 依赖注入

```swift
// 服务注册
class ServiceRegistry {
    static let shared = ServiceRegistry()

    private var services: [String: Any] = [:]

    func register<T>(_ type: T.Type, instance: T) {
        let key = String(describing: type)
        services[key] = instance
    }

    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        services[key] = factory
    }

    func resolve<T>() -> T {
        let key = String(describing: T.self)
        if let instance = services[key] as? T {
            return instance
        }

        if let factory = services[key] as? () -> T {
            let instance = factory()
            services[key] = instance
            return instance
        }

        fatalError("Service \(T.self) not registered")
    }
}

// 使用
extension ServiceRegistry {
    static func configureServices() {
        // 数据层
        shared.register(RecordRepository.self) {
            CoreDataRecordRepository(context: CoreDataStack.shared.context)
        }

        // 业务层
        shared.register(RecordService.self) {
            RecordService(
                repository: ServiceRegistry.shared.resolve() as RecordRepository,
                aiService: ServiceRegistry.shared.resolve() as AIService,
                searchService: ServiceRegistry.shared.resolve() as SearchService
            )
        }

        // 表现层
        shared.register(MainViewModel.self) {
            MainViewModel(
                recordService: ServiceRegistry.shared.resolve() as RecordService,
                aiService: ServiceRegistry.shared.resolve() as AIService
            )
        }
    }
}
```

---

## 7. 项目文件结构

### 7.1 推荐的文件组织

```
Sources/QuiteNote/
├── App/                           # 应用入口和主结构
│   ├── MainApp.swift             # 应用入口
│   ├── AppCoordinator.swift      # 应用协调器
│   ├── AppRouter.swift           # 路由管理
│   └── AppDelegate.swift         # 应用代理
│
├── Core/                         # 核心功能
│   ├── Constants/                # 常量定义
│   │   ├── AppConstants.swift
│   │   ├── APIConstants.swift
│   │   └── UIConstants.swift
│   ├── Extensions/               # 系统扩展
│   │   ├── String+Extensions.swift
│   │   ├── Date+Extensions.swift
│   │   ├── Array+Extensions.swift
│   │   └── Dictionary+Extensions.swift
│   └── Utils/                    # 通用工具
│       ├── Logger.swift
│       ├── Validator.swift
│       ├── Formatter.swift
│       └── Debouncer.swift
│
├── Data/                         # 数据层
│   ├── Models/                   # 数据模型
│   │   ├── Record.swift
│   │   ├── Preferences.swift
│   │   ├── Device.swift
│   │   └── AIResult.swift
│   ├── Repositories/             # 数据仓库
│   │   ├── RecordRepository.swift
│   │   ├── PreferenceRepository.swift
│   │   └── DeviceRepository.swift
│   ├── Persistence/              # 持久化
│   │   ├── CoreData/
│   │   │   ├── CoreDataStack.swift
│   │   │   ├── CDRecord.swift
│   │   │   └── Migrations/
│   │   └── Cache/
│   │       ├── RecordCache.swift
│   │       └── ImageCache.swift
│   ├── Services/                 # 数据服务
│   │   ├── SearchService.swift
│   │   ├── ExportService.swift
│   │   └── BackupService.swift
│   └── Extensions/               # 数据扩展
│       ├── Record+Extensions.swift
│       └── Date+Extensions.swift
│
├── Domain/                       # 业务领域
│   ├── Services/                 # 业务服务
│   │   ├── RecordService.swift
│   │   ├── AIService.swift
│   │   ├── DeviceService.swift
│   │   └── NotificationService.swift
│   ├── Managers/                 # 管理器
│   │   ├── RecordManager.swift
│   │   ├── AIManager.swift
│   │   ├── DeviceManager.swift
│   │   └── NotificationManager.swift
│   └── State/                    # 状态管理
│       ├── AppState.swift
│       ├── RecordState.swift
│       ├── AIState.swift
│       └── DeviceState.swift
│
├── Presentation/                   # 表现层
│   ├── Theme/                    # 主题系统
│   │   ├── Color+Theme.swift
│   │   ├── Font+Theme.swift
│   │   ├── Spacing+Theme.swift
│   │   ├── Shape+Theme.swift
│   │   ├── Animation+Theme.swift
│   │   └── ThemeManager.swift
│   ├── Components/               # UI 组件
│   │   ├── Foundation/           # 基础组件
│   │   │   ├── Buttons/
│   │   │   │   ├── PrimaryButton.swift
│   │   │   │   ├── SecondaryButton.swift
│   │   │   │   └── IconButton.swift
│   │   │   ├── Inputs/
│   │   │   │   ├── TextField.swift
│   │   │   │   ├── Toggle.swift
│   │   │   │   └── Slider.swift
│   │   │   ├── Typography/
│   │   │   │   ├── Text.swift
│   │   │   │   ├── Heading.swift
│   │   │   │   └── Caption.swift
│   │   │   └── Layouts/
│   │   │       ├── Container.swift
│   │   │       ├── Stack.swift
│   │   │       └── Grid.swift
│   │   ├── Business/             # 业务组件
│   │   │   ├── Records/
│   │   │   │   ├── RecordCard.swift
│   │   │   │   ├── RecordList.swift
│   │   │   │   └── RecordForm.swift
│   │   │   ├── Settings/
│   │   │   │   ├── SettingsCard.swift
│   │   │   │   ├── SettingsSection.swift
│   │   │   │   └── SettingsItem.swift
│   │   │   ├── Bluetooth/
│   │   │   │   ├── DeviceCard.swift
│   │   │   │   ├── DeviceList.swift
│   │   │   │   └── ConnectionStatus.swift
│   │   │   └── AI/
│   │   │       ├── AISummary.swift
│   │   │       ├── AIStatus.swift
│   │   │       └── AIProviderSelector.swift
│   │   └── Composite/            # 复合组件
│   │       ├── Panels/
│   │       │   ├── FloatingPanel.swift
│   │       │   ├── SettingsPanel.swift
│   │       │   └── DashboardPanel.swift
│   │       ├── Overlays/
│   │       │   ├── Toast.swift
│   │       │   ├── Dialog.swift
│   │       │   └── LoadingOverlay.swift
│   │       └── Navigation/
│   │           ├── TabBar.swift
│   │           ├── NavBar.swift
│   │           └── SideBar.swift
│   ├── Views/                    # 视图
│   │   ├── Main/
│   │   │   ├── DashboardView.swift
│   │   │   ├── SettingsView.swift
│   │   │   └── RecordListView.swift
│   │   └── Modals/
│   │       ├── ToastView.swift
│   │       ├── DialogView.swift
│   │       └── LoadingView.swift
│   ├── ViewModels/               # 视图模型
│   │   ├── MainViewModel.swift
│   │   ├── SettingsViewModel.swift
│   │   ├── RecordListViewModel.swift
│   │   └── RecordDetailViewModel.swift
│   └── Extensions/               # 视图扩展
│       ├── View+Theming.swift
│       ├── View+Animations.swift
│       └── View+Layout.swift
│
├── System/                       # 系统集成
│   ├── Services/                 # 系统服务
│   │   ├── StatusBarService.swift
│   │   ├── KeyboardShortcutService.swift
│   │   ├── ClipboardService.swift
│   │   └── NotificationService.swift
│   ├── Integrations/             # 系统集成
│   │   ├── NSStatusBar+Integration.swift
│   │   ├── NSEvent+Integration.swift
│   │   ├── NSPasteboard+Integration.swift
│   │   └── NSUserNotificationCenter+Integration.swift
│   └── Utils/                    # 系统工具
│       ├── SystemInfo.swift
│       └── PermissionChecker.swift
│
├── Device/                       # 设备连接
│   ├── Models/
│   │   └── Device.swift
│   ├── Services/
│   │   ├── BluetoothManager.swift
│   │   ├── DeviceDiscoveryService.swift
│   │   └── DeviceConfigurationService.swift
│   ├── Protocols/
│   │   ├── DeviceProtocol.swift
│   │   └── ButtonEventProtocol.swift
│   └── Utils/
│       ├── UUIDManager.swift
│       └── RSSICalculator.swift
│
├── AI/                           # AI 服务
│   ├── Models/
│   │   ├── AIResult.swift
│   │   ├── AIProvider.swift
│   │   └── AIConfiguration.swift
│   ├── Providers/
│   │   ├── LocalAIService.swift
│   │   ├── OpenAIService.swift
│   │   ├── AnthropicService.swift
│   │   └── AzureAIService.swift
│   ├── Engines/
│   │   ├── RuleBasedEngine.swift
│   │   └── MLBasedEngine.swift
│   └── Utils/
│       ├── TextProcessor.swift
│       ├── ResultValidator.swift
│       └── AICacheManager.swift
│
├── Security/                     # 安全模块
│   ├── Keychain/
│   │   ├── KeychainManager.swift
│   │   ├── KeychainItem.swift
│   │   └── KeychainError.swift
│   ├── Encryption/
│   │   ├── AESEncryption.swift
│   │   ├── HashGenerator.swift
│   │   └── SecureStorage.swift
│   └── Authentication/
│       ├── APIKeyManager.swift
│       └── PermissionManager.swift
│
└── Config/                       # 配置模块
    ├── Environment/
    │   ├── EnvironmentType.swift
    │   ├── EnvironmentConfig.swift
    │   └── FeatureFlags.swift
    ├── Settings/
    │   ├── AppSettings.swift
    │   ├── UserPreferences.swift
    │   └── SettingsManager.swift
    └── Constants/
        ├── AppConstants.swift
        ├── APIConstants.swift
        └── UIConstants.swift
```

### 7.2 文件命名规范

#### 7.2.1 文件类型后缀

| 类型 | 后缀 | 示例 |
|------|------|------|
| 视图 | View.swift | RecordListView.swift |
| 视图模型 | ViewModel.swift | RecordListViewModel.swift |
| 服务 | Service.swift | RecordService.swift |
| 管理器 | Manager.swift | BluetoothManager.swift |
| 仓库 | Repository.swift | RecordRepository.swift |
| 模型 | .swift | Record.swift |
| 扩展 | +Extensions.swift | String+Extensions.swift |
| 主题 | +Theme.swift | Color+Theme.swift |
| 协议 | Protocol.swift | RecordProtocol.swift |

#### 7.2.2 命名约定

```swift
// ✅ 正确：遵循命名约定
class RecordListView: View
class RecordListViewModel: ObservableObject
struct Record: Identifiable, Codable
protocol RecordService {
    func getRecords() async throws -> [Record]
}
extension String {
    func toCamelCase() -> String
}

// ❌ 错误：不一致的命名
class RecordList: View
class RecordListVM: ObservableObject
struct recordData: Identifiable
protocol RecordManager {
    func fetchRecords() -> [Record]
}
extension String {
    func camelCase() -> String
}
```

---

## 8. 设计模式应用

### 8.1 观察者模式 (Observer Pattern)

```swift
// 使用 Combine 框架
import Combine

class ObservableObject: ObservableObject {
    @Published var data: [String] = []
}

// 使用
class Observer: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []

    init(observable: ObservableObject) {
        observable.$data
            .sink { newData in
                print("Data changed: \(newData)")
            }
            .store(in: &cancellables)
    }
}
```

### 8.2 策略模式 (Strategy Pattern)

```swift
protocol SearchStrategy {
    func search(in records: [Record], query: String) -> [Record]
}

class ExactSearchStrategy: SearchStrategy {
    func search(in records: [Record], query: String) -> [Record] {
        return records.filter { $0.content.contains(query) }
    }
}

class FuzzySearchStrategy: SearchStrategy {
    func search(in records: [Record], query: String) -> [Record] {
        return records.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }
}

class SearchContext {
    var strategy: SearchStrategy

    init(strategy: SearchStrategy) {
        self.strategy = strategy
    }

    func executeSearch(in records: [Record], query: String) -> [Record] {
        return strategy.search(in: records, query: query)
    }
}
```

### 8.3 工厂模式 (Factory Pattern)

```swift
protocol ViewFactory {
    func createRecordListView() -> RecordListView
    func createSettingsView() -> SettingsView
    func createFloatingPanelView() -> FloatingPanelView
}

class SwiftUIFactory: ViewFactory {
    func createRecordListView() -> RecordListView {
        return RecordListView(viewModel: DIContainer.shared.resolve())
    }

    func createSettingsView() -> SettingsView {
        return SettingsView(viewModel: DIContainer.shared.resolve())
    }

    func createFloatingPanelView() -> FloatingPanelView {
        return FloatingPanelView(viewModel: DIContainer.shared.resolve())
    }
}
```

### 8.4 单例模式 (Singleton Pattern)

```swift
final class Singleton {
    static let shared = Singleton()

    private init() {}

    // 单例方法
}
```

### 8.5 命令模式 (Command Pattern)

```swift
protocol Command {
    func execute()
    func undo()
}

class AddRecordCommand: Command {
    private let record: Record
    private let recordService: RecordService

    init(record: Record, recordService: RecordService) {
        self.record = record
        self.recordService = recordService
    }

    func execute() {
        Task {
            try await recordService.addRecord(record)
        }
    }

    func undo() {
        Task {
            try await recordService.deleteRecord(record.id)
        }
    }
}
```

---

## 9. 扩展性考虑

### 9.1 插件化架构

```swift
protocol Plugin {
    var name: String { get }
    var version: String { get }
    func initialize(in context: PluginContext)
    func deinitialize()
}

protocol PluginContext {
    func registerService<T>(_ service: T)
    func getService<T>() -> T?
    func registerView(_ view: AnyView, at location: ViewLocation)
}

class PluginManager {
    private var plugins: [Plugin] = []

    func loadPlugin(_ plugin: Plugin, context: PluginContext) {
        plugins.append(plugin)
        plugin.initialize(in: context)
    }

    func unloadPlugin(_ plugin: Plugin) {
        plugin.deinitialize()
        plugins.removeAll { $0.name == plugin.name }
    }
}
```

### 9.2 主题系统扩展

```swift
protocol ThemeProvider {
    var colors: ColorTheme { get }
    var fonts: FontTheme { get }
    var spacing: SpacingTheme { get }
    var shapes: ShapeTheme { get }
    var animations: AnimationTheme { get }
}

class CustomThemeProvider: ThemeProvider {
    var colors: ColorTheme
    var fonts: FontTheme
    var spacing: SpacingTheme
    var shapes: ShapeTheme
    var animations: AnimationTheme

    init(colors: ColorTheme, fonts: FontTheme, spacing: SpacingTheme, shapes: ShapeTheme, animations: AnimationTheme) {
        self.colors = colors
        self.fonts = fonts
        self.spacing = spacing
        self.shapes = shapes
        self.animations = animations
    }
}
```

### 9.3 国际化支持

```swift
protocol Localizable {
    var localized: String { get }
}

extension String: Localizable {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}

class LocalizationManager {
    static let shared = LocalizationManager()

    private init() {}

    func localizedString(_ key: String, arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return String(format: format, arguments: arguments)
    }
}
```

---

## 10. 性能优化策略

### 10.1 视图性能优化

```swift
// 使用 @ViewBuilder 减少视图构建开销
@ViewBuilder
func buildContent() -> some View {
    if isLoading {
        LoadingView()
    } else if records.isEmpty {
        EmptyStateView()
    } else {
        RecordListView(records: records)
    }
}

// 使用 @StateObject 避免重复初始化
@StateObject private var viewModel = RecordListViewModel()

// 使用 LazyVStack 提升列表性能
LazyVStack {
    ForEach(records) { record in
        RecordRowView(record: record)
    }
}
```

### 10.2 数据性能优化

```swift
// 使用分页加载
class PagedRecordService {
    func loadPage(page: Int, pageSize: Int) async throws -> [Record] {
        // 实现分页逻辑
    }
}

// 使用缓存
class CachedRecordService {
    private let cache = NSCache<NSString, NSArray>()

    func getCachedRecords() -> [Record]? {
        guard let cached = cache.object(forKey: "records" as NSString) as? [Record] else {
            return nil
        }
        return cached
    }
}
```

### 10.3 内存管理

```swift
// 使用 weak 引用避免循环引用
class ViewModel: ObservableObject {
    weak var delegate: ViewModelDelegate?

    deinit {
        print("ViewModel deallocated")
    }
}

// 及时释放不需要的资源
class ResourceManager {
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
```

---

## 总结

本架构设计方案提供了：

1. **清晰的分层结构**：表现层、业务层、数据层、基础设施层
2. **模块化的组件设计**：基础组件、业务组件、复合组件
3. **完整的功能分块**：数据管理、设备连接、AI服务、用户界面、系统集成
4. **可扩展的架构**：插件化、主题系统、国际化
5. **性能优化策略**：视图优化、数据优化、内存管理
6. **标准化的开发流程**：依赖注入、设计模式、命名规范

这个架构设计为 QuiteNote 的长期发展奠定了坚实的基础，支持功能的持续演进和性能的持续优化。

---

**文档结束**