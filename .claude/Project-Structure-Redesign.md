# QuiteNote 项目文件结构重新组织方案

> 版本：2.0
> 日期：2025-12-09
> 作者：Claude Code

## 目录

1. [重新组织目标](#1-重新组织目标)
2. [新文件结构](#2-新文件结构)
3. [迁移指南](#3-迁移指南)
4. [文件模板](#4-文件模板)
5. [实施计划](#5-实施计划)
6. [验证清单](#6-验证清单)

---

## 1. 重新组织目标

### 1.1 当前问题分析

基于现有代码库分析，发现以下问题：

1. **文件组织混乱**
   - 功能相关文件分散在不同目录
   - 缺乏清晰的模块边界
   - UI 和业务逻辑混合

2. **架构不清晰**
   - 层次结构不明确
   - 依赖关系混乱
   - 缺乏统一的抽象层

3. **可维护性差**
   - 难以定位相关代码
   - 重复代码较多
   - 修改影响范围难评估

4. **可扩展性不足**
   - 新功能添加困难
   - 模块间耦合度高
   - 缺乏插件化支持

### 1.2 重新组织目标

1. **清晰的模块化结构**
   - 按功能模块组织文件
   - 明确的模块边界
   - 低耦合高内聚

2. **标准的分层架构**
   - 表现层、业务层、数据层清晰分离
   - 标准的依赖方向
   - 统一的接口定义

3. **易于维护和扩展**
   - 相关代码集中管理
   - 标准的文件模板
   - 完善的文档和注释

4. **支持团队协作**
   - 明确的代码规范
   - 统一的开发流程
   - 便于代码审查

---

## 2. 新文件结构

### 2.1 总体结构

```
Sources/QuiteNote/
├── App/                           # 应用入口和主结构
│   ├── MainApp.swift             # 应用入口点
│   ├── AppCoordinator.swift      # 应用协调器
│   ├── AppRouter.swift           # 路由管理
│   └── AppDelegate.swift         # 应用代理
│
├── Core/                         # 核心基础设施
│   ├── Constants/                # 常量定义
│   │   ├── AppConstants.swift
│   │   ├── APIConstants.swift
│   │   └── UIConstants.swift
│   ├── Extensions/               # 系统扩展
│   │   ├── String+Extensions.swift
│   │   ├── Date+Extensions.swift
│   │   ├── Array+Extensions.swift
│   │   ├── Dictionary+Extensions.swift
│   │   └── View+Extensions.swift
│   └── Utils/                    # 通用工具
│       ├── Logger.swift
│       ├── Validator.swift
│       ├── Formatter.swift
│       ├── Debouncer.swift
│       └── PerformanceMonitor.swift
│
├── Presentation/                   # 表现层 (SwiftUI Views)
│   ├── Theme/                    # 主题系统
│   │   ├── Color+Theme.swift
│   │   ├── Font+Theme.swift
│   │   ├── Spacing+Theme.swift
│   │   ├── Shape+Theme.swift
│   │   ├── Animation+Theme.swift
│   │   └── ThemeManager.swift
│   ├── Components/               # UI 组件库
│   │   ├── Foundation/           # 基础组件
│   │   │   ├── Buttons/
│   │   │   │   ├── PrimaryButton.swift
│   │   │   │   ├── SecondaryButton.swift
│   │   │   │   ├── IconButton.swift
│   │   │   │   └── ThemeButtonStyle.swift
│   │   │   ├── Inputs/
│   │   │   │   ├── TextField.swift
│   │   │   │   ├── Toggle.swift
│   │   │   │   ├── Slider.swift
│   │   │   │   └── SearchBar.swift
│   │   │   ├── Typography/
│   │   │   │   ├── Text.swift
│   │   │   │   ├── Heading.swift
│   │   │   │   └── Caption.swift
│   │   │   └── Layouts/
│   │   │       ├── Container.swift
│   │   │       ├── Stack.swift
│   │   │       ├── Grid.swift
│   │   │       └── Panel.swift
│   │   ├── Business/             # 业务组件
│   │   │   ├── Records/
│   │   │   │   ├── RecordCard.swift
│   │   │   │   ├── RecordList.swift
│   │   │   │   ├── RecordForm.swift
│   │   │   │   └── RecordDetail.swift
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
│   ├── Views/                    # 页面视图
│   │   ├── Main/
│   │   │   ├── DashboardView.swift
│   │   │   ├── SettingsView.swift
│   │   │   ├── RecordListView.swift
│   │   │   └── RecordDetailView.swift
│   │   └── Modals/
│   │       ├── ToastView.swift
│   │       ├── DialogView.swift
│   │       └── LoadingView.swift
│   └── ViewModels/               # 视图模型
│       ├── Main/
│       │   ├── MainViewModel.swift
│       │   ├── DashboardViewModel.swift
│       │   ├── SettingsViewModel.swift
│       │   └── RecordListViewModel.swift
│       └── Detail/
│           ├── RecordDetailViewModel.swift
│           └── SettingsDetailViewModel.swift
│
├── Business/                     # 业务层 (Services & Managers)
│   ├── Services/                 # 业务服务
│   │   ├── RecordService.swift
│   │   ├── AIService.swift
│   │   ├── DeviceService.swift
│   │   ├── NotificationService.swift
│   │   ├── SearchService.swift
│   │   ├── ExportService.swift
│   │   └── BackupService.swift
│   ├── Managers/                 # 管理器
│   │   ├── RecordManager.swift
│   │   ├── AIManager.swift
│   │   ├── DeviceManager.swift
│   │   ├── NotificationManager.swift
│   │   ├── ThemeManager.swift
│   │   └── PermissionManager.swift
│   ├── State/                    # 状态管理
│   │   ├── AppState.swift
│   │   ├── RecordState.swift
│   │   ├── AIState.swift
│   │   ├── DeviceState.swift
│   │   └── SettingsState.swift
│   └── UseCases/                 # 用例（可选）
│       ├── RecordUseCases.swift
│       ├── AISummaryUseCases.swift
│       └── DeviceConnectionUseCases.swift
│
├── Data/                         # 数据层 (Models & Repositories)
│   ├── Models/                   # 数据模型
│   │   ├── Record.swift
│   │   ├── Preferences.swift
│   │   ├── Device.swift
│   │   ├── AIResult.swift
│   │   ├── SearchResult.swift
│   │   └── ExportResult.swift
│   ├── Repositories/             # 数据仓库
│   │   ├── RecordRepository.swift
│   │   ├── PreferenceRepository.swift
│   │   ├── DeviceRepository.swift
│   │   └── ExportRepository.swift
│   ├── Persistence/              # 持久化
│   │   ├── CoreData/
│   │   │   ├── CoreDataStack.swift
│   │   │   ├── CDRecord.swift
│   │   │   └── Migrations/
│   │   │       ├── Migration_v1_0_to_v1_1.swift
│   │   │       └── Migration_v1_1_to_v1_2.swift
│   │   └── Cache/
│   │       ├── RecordCache.swift
│   │       └── ImageCache.swift
│   ├── Services/                 # 数据服务
│   │   ├── SearchService.swift
│   │   ├── ExportService.swift
│   │   └── BackupService.swift
│   └── Extensions/               # 数据扩展
│       ├── Record+Extensions.swift
│       ├── Date+Extensions.swift
│       └── Codable+Extensions.swift
│
├── Infrastructure/               # 基础设施层
│   ├── System/                   # 系统集成
│   │   ├── Services/
│   │   │   ├── StatusBarService.swift
│   │   │   ├── KeyboardShortcutService.swift
│   │   │   ├── ClipboardService.swift
│   │   │   └── NotificationService.swift
│   │   ├── Integrations/
│   │   │   ├── NSStatusBar+Integration.swift
│   │   │   ├── NSEvent+Integration.swift
│   │   │   ├── NSPasteboard+Integration.swift
│   │   │   └── NSUserNotificationCenter+Integration.swift
│   │   └── Utils/
│   │       ├── SystemInfo.swift
│   │       └── PermissionChecker.swift
│   ├── Device/                   # 设备连接
│   │   ├── Models/
│   │   │   └── Device.swift
│   │   ├── Services/
│   │   │   ├── BluetoothManager.swift
│   │   │   ├── DeviceDiscoveryService.swift
│   │   │   └── DeviceConfigurationService.swift
│   │   ├── Protocols/
│   │   │   ├── DeviceProtocol.swift
│   │   │   └── ButtonEventProtocol.swift
│   │   └── Utils/
│   │       ├── UUIDManager.swift
│   │       └── RSSICalculator.swift
│   ├── AI/                       # AI 服务
│   │   ├── Models/
│   │   │   ├── AIResult.swift
│   │   │   ├── AIProvider.swift
│   │   │   └── AIConfiguration.swift
│   │   ├── Providers/
│   │   │   ├── LocalAIService.swift
│   │   │   ├── OpenAIService.swift
│   │   │   ├── AnthropicService.swift
│   │   │   └── AzureAIService.swift
│   │   ├── Engines/
│   │   │   ├── RuleBasedEngine.swift
│   │   │   └── MLBasedEngine.swift
│   │   └── Utils/
│   │       ├── TextProcessor.swift
│   │       ├── ResultValidator.swift
│   │       └── AICacheManager.swift
│   ├── Security/                 # 安全模块
│   │   ├── Keychain/
│   │   │   ├── KeychainManager.swift
│   │   │   ├── KeychainItem.swift
│   │   │   └── KeychainError.swift
│   │   ├── Encryption/
│   │   │   ├── AESEncryption.swift
│   │   │   ├── HashGenerator.swift
│   │   │   └── SecureStorage.swift
│   │   └── Authentication/
│   │       ├── APIKeyManager.swift
│   │       └── PermissionManager.swift
│   └── Network/                  # 网络模块
│       ├── Services/
│       │   ├── NetworkService.swift
│       │   └── APIClient.swift
│       ├── Models/
│       │   ├── APIError.swift
│       │   └── NetworkResponse.swift
│       └── Utils/
│           ├── RequestBuilder.swift
│           └── ResponseParser.swift
│
└── Dependencies/                 # 依赖管理
    ├── ServiceContainer.swift    # 依赖注入容器
    ├── ServiceRegistry.swift     # 服务注册
    └── DependencyGraph.swift     # 依赖图（可选）
```

### 2.2 文件结构说明

#### 2.2.1 按层组织

**Presentation Layer (表现层)**
- **职责**：用户界面展示、用户交互处理
- **特点**：依赖 Business Layer，不直接访问 Data Layer
- **技术**：SwiftUI、AppKit 集成

**Business Layer (业务层)**
- **职责**：业务逻辑处理、服务协调、状态管理
- **特点**：依赖 Data Layer 和 Infrastructure Layer
- **技术**：协议、依赖注入、状态管理

**Data Layer (数据层)**
- **职责**：数据模型定义、数据访问、持久化
- **特点**：被 Business Layer 依赖
- **技术**：Core Data、Repository 模式

**Infrastructure Layer (基础设施层)**
- **职责**：系统集成、外部服务、安全、网络
- **特点**：提供基础服务支持
- **技术**：平台 API、第三方服务

#### 2.2.2 按功能模块组织

**Records (记录管理)**
- 数据模型：Record, CDRecord
- 服务：RecordService, RecordRepository
- UI：RecordCard, RecordList, RecordDetail
- 视图模型：RecordListViewModel, RecordDetailViewModel

**AI (人工智能)**
- 服务：AIService, LocalAIService, OpenAIService
- UI：AISummary, AIProviderSelector
- 状态：AIState

**Device (设备连接)**
- 服务：DeviceService, BluetoothManager
- UI：DeviceCard, DeviceList, ConnectionStatus
- 协议：DeviceProtocol, ButtonEventProtocol

**Settings (设置)**
- 数据模型：Preferences
- 服务：PreferenceRepository
- UI：SettingsCard, SettingsSection, SettingsItem
- 视图模型：SettingsViewModel

**System (系统集成)**
- 服务：StatusBarService, KeyboardShortcutService
- 集成：NSStatusBar+Integration, NSEvent+Integration

---

## 3. 迁移指南

### 3.1 迁移步骤

#### 步骤 1：创建新目录结构

```bash
# 在项目根目录执行
mkdir -p Sources/QuiteNote/Presentation/Theme
mkdir -p Sources/QuiteNote/Presentation/Components/Foundation/Buttons
mkdir -p Sources/QuiteNote/Presentation/Components/Foundation/Inputs
mkdir -p Sources/QuiteNote/Presentation/Components/Foundation/Typography
mkdir -p Sources/QuiteNote/Presentation/Components/Foundation/Layouts
mkdir -p Sources/QuiteNote/Presentation/Components/Business/Records
mkdir -p Sources/QuiteNote/Presentation/Components/Business/Settings
mkdir -p Sources/QuiteNote/Presentation/Components/Business/Bluetooth
mkdir -p Sources/QuiteNote/Presentation/Components/Business/AI
mkdir -p Sources/QuiteNote/Presentation/Components/Composite/Panels
mkdir -p Sources/QuiteNote/Presentation/Components/Composite/Overlays
mkdir -p Sources/QuiteNote/Presentation/Components/Composite/Navigation
mkdir -p Sources/QuiteNote/Presentation/Views/Main
mkdir -p Sources/QuiteNote/Presentation/Views/Modals
mkdir -p Sources/QuiteNote/Presentation/ViewModels/Main
mkdir -p Sources/QuiteNote/Presentation/ViewModels/Detail
mkdir -p Sources/QuiteNote/Business/Services
mkdir -p Sources/QuiteNote/Business/Managers
mkdir -p Sources/QuiteNote/Business/State
mkdir -p Sources/QuiteNote/Data/Models
mkdir -p Sources/QuiteNote/Data/Repositories
mkdir -p Sources/QuiteNote/Data/Persistence/CoreData
mkdir -p Sources/QuiteNote/Data/Persistence/Cache
mkdir -p Sources/QuiteNote/Data/Services
mkdir -p Sources/QuiteNote/Data/Extensions
mkdir -p Sources/QuiteNote/Infrastructure/System/Services
mkdir -p Sources/QuiteNote/Infrastructure/System/Integrations
mkdir -p Sources/QuiteNote/Infrastructure/System/Utils
mkdir -p Sources/QuiteNote/Infrastructure/Device/Models
mkdir -p Sources/QuiteNote/Infrastructure/Device/Services
mkdir -p Sources/QuiteNote/Infrastructure/Device/Protocols
mkdir -p Sources/QuiteNote/Infrastructure/Device/Utils
mkdir -p Sources/QuiteNote/Infrastructure/AI/Models
mkdir -p Sources/QuiteNote/Infrastructure/AI/Providers
mkdir -p Sources/QuiteNote/Infrastructure/AI/Engines
mkdir -p Sources/QuiteNote/Infrastructure/AI/Utils
mkdir -p Sources/QuiteNote/Infrastructure/Security/Keychain
mkdir -p Sources/QuiteNote/Infrastructure/Security/Encryption
mkdir -p Sources/QuiteNote/Infrastructure/Security/Authentication
mkdir -p Sources/QuiteNote/Infrastructure/Network/Services
mkdir -p Sources/QuiteNote/Infrastructure/Network/Models
mkdir -p Sources/QuiteNote/Infrastructure/Network/Utils
mkdir -p Sources/QuiteNote/Core/Constants
mkdir -p Sources/QuiteNote/Core/Extensions
mkdir -p Sources/QuiteNote/Core/Utils
mkdir -p Sources/QuiteNote/App
mkdir -p Sources/QuiteNote/Dependencies
```

#### 步骤 2：迁移主题系统

```bash
# 迁移现有的主题文件
cp Sources/QuiteNote/UI/Theme/Color+Theme.swift Sources/QuiteNote/Presentation/Theme/
cp Sources/QuiteNote/UI/Theme/Font+Theme.swift Sources/QuiteNote/Presentation/Theme/
cp Sources/QuiteNote/UI/Theme/Spacing+Theme.swift Sources/QuiteNote/Presentation/Theme/
cp Sources/QuiteNote/UI/Theme/Shape+Theme.swift Sources/QuiteNote/Presentation/Theme/
cp Sources/QuiteNote/UI/Theme/Animation+Theme.swift Sources/QuiteNote/Presentation/Theme/
```

#### 步骤 3：迁移核心组件

```bash
# 迁移基础组件
cp Sources/QuiteNote/UI/Icon.swift Sources/QuiteNote/Presentation/Components/Foundation/Buttons/IconButton.swift
cp Sources/QuiteNote/UI/NativeSlider.swift Sources/QuiteNote/Presentation/Components/Foundation/Inputs/Slider.swift
```

#### 步骤 4：迁移业务组件

```bash
# 迁移记录相关组件
cp Sources/QuiteNote/UI/RecordCardView.swift Sources/QuiteNote/Presentation/Components/Business/Records/RecordCard.swift
cp Sources/QuiteNote/UI/HeatmapView.swift Sources/QuiteNote/Presentation/Components/Business/Records/Heatmap.swift
```

#### 步骤 5：迁移设置组件

```bash
# 迁移设置相关
cp Sources/QuiteNote/UI/SettingsOverlayView.swift Sources/QuiteNote/Presentation/Components/Composite/Panels/SettingsPanel.swift
cp Sources/QuiteNote/Preferences/PreferencesManager.swift Sources/QuiteNote/Data/Models/Preferences.swift
```

#### 步骤 6：迁移服务

```bash
# 迁移服务
cp Sources/QuiteNote/Records/RecordStore.swift Sources/QuiteNote/Business/Services/RecordService.swift
cp Sources/QuiteNote/AI/AIService.swift Sources/QuiteNote/Infrastructure/AI/Providers/OpenAIService.swift
cp Sources/QuiteNote/Bluetooth/BluetoothManager.swift Sources/QuiteNote/Infrastructure/Device/Services/BluetoothManager.swift
cp Sources/QuiteNote/Clipboard/ClipboardService.swift Sources/QuiteNote/Infrastructure/System/Services/ClipboardService.swift
```

#### 步骤 7：迁移数据模型

```bash
# 迁移数据模型
cp Sources/QuiteNote/Models/Record.swift Sources/QuiteNote/Data/Models/
cp Sources/QuiteNote/Models/Preferences.swift Sources/QuiteNote/Data/Models/
cp Sources/QuiteNote/Models/Device.swift Sources/QuiteNote/Data/Models/
```

#### 步骤 8：迁移持久化

```bash
# 迁移 Core Data
cp Sources/QuiteNote/Persistence/CoreDataStack.swift Sources/QuiteNote/Data/Persistence/CoreData/
cp Sources/QuiteNote/Persistence/CDRecord.swift Sources/QuiteNote/Data/Persistence/CoreData/
```

#### 步骤 9：迁移基础设施

```bash
# 迁移安全相关
cp Sources/QuiteNote/Security/KeychainHelper.swift Sources/QuiteNote/Infrastructure/Security/Keychain/

# 迁移系统集成
cp Sources/QuiteNote/Menu/StatusBarController.swift Sources/QuiteNote/Infrastructure/System/Services/StatusBarService.swift
cp Sources/QuiteNote/Input/KeyboardShortcutManager.swift Sources/QuiteNote/Infrastructure/System/Services/KeyboardShortcutService.swift
```

#### 步骤 10：迁移应用入口

```bash
# 迁移应用入口
cp Sources/QuiteNote/App/MainApp.swift Sources/QuiteNote/App/
```

### 3.2 文件重命名和重构

#### 3.2.1 服务重命名

```bash
# 重命名服务文件以符合新架构
mv Sources/QuiteNote/Business/Services/RecordStore.swift Sources/QuiteNote/Business/Services/RecordService.swift
mv Sources/QuiteNote/Business/Services/AIService.swift Sources/QuiteNote/Infrastructure/AI/Providers/OpenAIService.swift
```

#### 3.2.2 组件重命名

```bash
# 重命名组件以符合新结构
mv Sources/QuiteNote/Presentation/Components/Business/Records/RecordCardView.swift Sources/QuiteNote/Presentation/Components/Business/Records/RecordCard.swift
```

#### 3.2.3 视图模型创建

为每个主要视图创建对应的 ViewModel：

```swift
// Sources/QuiteNote/Presentation/ViewModels/Main/RecordListViewModel.swift
@MainActor
final class RecordListViewModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let recordService: RecordServiceProtocol
    private let searchService: SearchServiceProtocol

    init(
        recordService: RecordServiceProtocol,
        searchService: SearchServiceProtocol
    ) {
        self.recordService = recordService
        self.searchService = searchService
    }

    @MainActor
    func loadRecords() async {
        isLoading = true
        errorMessage = nil

        do {
            records = try await recordService.getAllRecords()
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }

    func searchRecords(query: String) async {
        isLoading = true
        errorMessage = nil

        do {
            records = try await searchService.search(query: query)
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }
}
```

### 3.3 依赖注入配置

创建或更新 Service Container：

```swift
// Sources/QuiteNote/Dependencies/ServiceContainer.swift
final class ServiceContainer {
    static let shared = ServiceContainer()

    private var services: [String: Any] = [:]

    private init() {}

    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: T.self)
        services[key] = factory
    }

    func resolve<T>() -> T {
        let key = String(describing: T.self)
        guard let factory = services[key] as? () -> T else {
            fatalError("Service \(T.self) not registered")
        }
        return factory()
    }
}

// Sources/QuiteNote/Dependencies/ServiceRegistry.swift
extension ServiceContainer {
    func configure() {
        configureCoreServices()
        configureDataServices()
        configureBusinessServices()
        configurePresentationServices()
    }

    private func configureCoreServices() {
        // 日志服务
        register(LoggerProtocol.self) {
            LoggerServiceImpl()
        }

        // 配置管理
        register(ConfigProtocol.self) {
            ConfigServiceImpl()
        }
    }

    private func configureDataServices() {
        // Core Data
        register(NSManagedObjectContext.self) {
            CoreDataStack.shared.context
        }

        // Record Repository
        register(RecordRepositoryProtocol.self) {
            CoreDataRecordRepository(context: self.resolve() as NSManagedObjectContext)
        }

        // Preference Repository
        register(PreferenceRepositoryProtocol.self) {
            UserDefaultsPreferenceRepository()
        }

        // Search Service
        register(SearchServiceProtocol.self) {
            SearchServiceImpl(repository: self.resolve() as RecordRepositoryProtocol)
        }
    }

    private func configureBusinessServices() {
        // Record Service
        register(RecordServiceProtocol.self) {
            RecordServiceImpl(
                repository: self.resolve() as RecordRepositoryProtocol,
                searchService: self.resolve() as SearchServiceProtocol,
                logger: self.resolve() as LoggerProtocol
            )
        }

        // AI Service
        register(AIServiceProtocol.self) {
            AIServiceImpl(
                providers: [
                    LocalAIService(),
                    OpenAIService()
                ]
            )
        }

        // Device Service
        register(DeviceServiceProtocol.self) {
            DeviceServiceImpl(
                bluetoothManager: self.resolve() as BluetoothManagerProtocol
            )
        }

        // Notification Service
        register(NotificationServiceProtocol.self) {
            LocalNotificationService()
        }
    }

    private func configurePresentationServices() {
        // Main View Model
        register(MainViewModel.self) {
            MainViewModel(
                recordService: self.resolve() as RecordServiceProtocol,
                deviceService: self.resolve() as DeviceServiceProtocol,
                aiService: self.resolve() as AIServiceProtocol
            )
        }

        // Record List View Model
        register(RecordListViewModel.self) {
            RecordListViewModel(
                recordService: self.resolve() as RecordServiceProtocol,
                searchService: self.resolve() as SearchServiceProtocol
            )
        }

        // Settings View Model
        register(SettingsViewModel.self) {
            SettingsViewModel(
                preferenceRepository: self.resolve() as PreferenceRepositoryProtocol,
                themeManager: self.resolve() as ThemeManagerProtocol
            )
        }
    }
}
```

### 3.4 更新导入路径

更新所有文件中的导入语句：

```swift
// 旧的导入
import SwiftUI
import AppKit

// 新的导入（如果需要）
import Presentation
import Business
import Data
import Infrastructure
import Core
import Dependencies
```

### 3.5 更新应用入口

更新 MainApp.swift 以使用新的架构：

```swift
// Sources/QuiteNote/App/MainApp.swift
@main
struct QuiteNoteApp: App {
    @StateObject private var mainViewModel: MainViewModel

    init() {
        // 配置依赖注入
        ServiceContainer.shared.configure()

        // 获取主视图模型
        _mainViewModel = StateObject(
            wrappedValue: ServiceContainer.shared.resolve() as MainViewModel
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mainViewModel)
                .environment(\.managedObjectContext, ServiceContainer.shared.resolve())
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var mainViewModel: MainViewModel

    var body: some View {
        Group {
            if mainViewModel.isFirstLaunch {
                OnboardingView()
            } else {
                DashboardView()
            }
        }
        .onAppear {
            mainViewModel.initializeApp()
        }
    }
}
```

---

## 4. 文件模板

### 4.1 View 模板

```swift
// Sources/QuiteNote/Presentation/Components/Business/Records/RecordCard.swift
import SwiftUI

/// 单个记录卡片视图
///
/// 此视图显示一条记录的基本信息，包括标题、内容预览和操作按钮。
/// 支持展开/收起状态切换，以及星标、删除等操作。
///
/// # Example
/// ```swift
/// RecordCard(record: record, isExpanded: $isExpanded)
/// ```
///
/// - Note: 此视图是纯展示性的，不包含业务逻辑
/// - SeeAlso: `RecordList`, `RecordDetail`
struct RecordCard: View {
    // MARK: - Properties

    let record: Record
    @Binding var isExpanded: Bool
    @State private var isStarred: Bool
    @State private var showingDeleteConfirmation = false

    @StateObject private var viewModel: RecordCardViewModel

    // 环境变量
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - Init

    init(
        record: Record,
        isExpanded: Binding<Bool>,
        viewModel: RecordCardViewModel? = nil
    ) {
        self.record = record
        self._isExpanded = isExpanded
        self._isStarred = State(initialValue: record.isStarred)
        self._viewModel = StateObject(
            wrappedValue: viewModel ?? RecordCardViewModel()
        )
    }

    // MARK: - Body

    var body: some View {
        cardContent
            .padding(ThemeSpacing.p3.rawValue)
            .background(cardBackground)
            .cornerRadius(ThemeRadius.lg.rawValue)
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            .contextMenu {
                contextMenuContent
            }
            .sheet(isPresented: $showingDeleteConfirmation) {
                deleteConfirmationSheet
            }
    }

    // MARK: - Private Views

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
            headerView
            contentView
            footerView
        }
        .padding(ThemeSpacing.p3.rawValue)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: ThemeSpacing.p1.rawValue) {
                Text(record.title)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                    .lineLimit(2)

                HStack {
                    Text(record.formattedDate)
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)

                    Spacer()

                    AIIndicator(isProcessed: record.isAIProcessed)
                }
            }

            Spacer()

            StarButton(
                isStarred: $isStarred,
                action: toggleStarred
            )
        }
    }

    private var contentView: some View {
        Text(record.contentPreview)
            .font(.themeBody)
            .foregroundColor(.themeTextPrimary)
            .lineLimit(isExpanded ? nil : 3)
            .multilineTextAlignment(.leading)
    }

    private var footerView: some View {
        HStack {
            if let aiSummary = record.aiSummary, !aiSummary.isEmpty {
                AISummaryView(summary: aiSummary)
            }

            Spacer()

            ToggleButton(
                isToggled: $isExpanded,
                onLabel: "收起",
                offLabel: "展开"
            )
        }
    }

    private var cardBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.themeCard.opacity(0.8),
                Color.themeCard.opacity(1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var contextMenuContent: some View {
        Group {
            Button(action: {
                toggleStarred()
            }) {
                Label(isStarred ? "取消星标" : "添加星标", systemImage: isStarred ? "star.fill" : "star")
            }

            Button(action: {
                viewModel.copyToClipboard(record.content)
            }) {
                Label("复制内容", systemImage: "doc.on.doc")
            }

            Divider()

            Button(action: {
                showingDeleteConfirmation = true
            }) {
                Label("删除", systemImage: "trash")
                    .foregroundColor(.themeRed500)
            }
        }
    }

    private var deleteConfirmationSheet: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            VStack(spacing: ThemeSpacing.p2.rawValue) {
                Text("确认删除")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Text("确定要删除这条记录吗？此操作无法撤销。")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: ThemeSpacing.p3.rawValue) {
                Button("取消") {
                    showingDeleteConfirmation = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("删除") {
                    deleteRecord()
                    showingDeleteConfirmation = false
                }
                .buttonStyle(DangerButtonStyle())
            }
        }
        .padding(ThemeSpacing.p4.rawValue)
    }

    // MARK: - Actions

    private func toggleStarred() {
        isStarred.toggle()
        viewModel.toggleStarred(for: record.id, isStarred: isStarred)
    }

    private func deleteRecord() {
        viewModel.deleteRecord(record.id)
    }
}

// MARK: - Previews
#preview {
    RecordCard(
        record: Record.sample,
        isExpanded: .constant(false)
    )
    .preferredColorScheme(.dark)
    .background(Color.themeBackground)
}
```

### 4.2 ViewModel 模板

```swift
// Sources/QuiteNote/Presentation/ViewModels/Detail/RecordDetailViewModel.swift
import Foundation
import Combine

/// 记录详情视图模型
///
/// 负责管理记录详情页面的状态和业务逻辑，
/// 包括记录加载、编辑、删除、AI处理等功能。
@MainActor
final class RecordDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var record: Record?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isEditing = false
    @Published var showingDeleteConfirmation = false
    @Published var showingAISummary = false

    // 编辑状态
    @Published var editingTitle = ""
    @Published var editingContent = ""

    // MARK: - Private Properties

    private let recordService: RecordServiceProtocol
    private let aiService: AIServiceProtocol
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    /// 初始化 RecordDetailViewModel
    /// - Parameters:
    ///   - recordService: 记录服务
    ///   - aiService: AI 服务
    init(
        recordService: RecordServiceProtocol,
        aiService: AIServiceProtocol
    ) {
        self.recordService = recordService
        self.aiService = aiService
    }

    // MARK: - Public Methods

    /// 加载记录
    /// - Parameter recordId: 记录 ID
    func loadRecord(_ recordId: UUID) async {
        isLoading = true
        errorMessage = nil

        do {
            record = try await recordService.getRecord(id: recordId)
            setupEditingState()
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }

    /// 开始编辑
    func startEditing() {
        guard let record = record else { return }
        isEditing = true
        editingTitle = record.title
        editingContent = record.content
    }

    /// 保存编辑
    func saveEditing() async {
        guard let record = record else { return }

        isLoading = true
        errorMessage = nil

        do {
            let updatedRecord = Record(
                id: record.id,
                title: editingTitle,
                content: editingContent,
                timestamp: record.timestamp,
                sha1: record.sha1,
                isStarred: record.isStarred,
                aiSummary: record.aiSummary,
                isAIProcessed: record.isAIProcessed,
                aiProvider: record.aiProvider
            )

            let savedRecord = try await recordService.updateRecord(updatedRecord)
            self.record = savedRecord
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }

    /// 取消编辑
    func cancelEditing() {
        setupEditingState()
        isEditing = false
    }

    /// 删除记录
    func deleteRecord() async {
        guard let record = record else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await recordService.deleteRecord(id: record.id)
            self.record = nil
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }

    /// AI 智能总结
    func generateAISummary() async {
        guard let record = record, !record.isAIProcessed else { return }

        isLoading = true
        errorMessage = nil

        do {
            let summary = try await aiService.summarize(
                text: record.content,
                options: AISummaryOptions(
                    maxTokens: 150,
                    temperature: 0.7
                )
            )

            var updatedRecord = record
            updatedRecord.aiSummary = summary
            updatedRecord.isAIProcessed = true
            updatedRecord.aiProvider = aiService.currentProvider.name

            let savedRecord = try await recordService.updateRecord(updatedRecord)
            self.record = savedRecord
            showingAISummary = true
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }

    /// 复制内容到剪贴板
    func copyContentToClipboard() {
        guard let record = record else { return }
        NSPasteboard.general.copyToClipboard(record.content)
    }

    /// 分享记录
    func shareRecord() {
        guard let record = record else { return }
        let items: [Any] = [record.content]
        NSPasteboard.general.writeObjects(items)
    }

    // MARK: - Private Methods

    private func setupEditingState() {
        guard let record = record else { return }
        editingTitle = record.title
        editingContent = record.content
    }
}

// MARK: - Extensions
private extension NSPasteboard {
    func copyToClipboard(_ string: String) {
        clearContents()
        setData(string.data(using: .utf8)!, forType: .string)
    }

    func writeObjects(_ objects: [Any]) {
        clearContents()
        // 实现分享逻辑
    }
}
```

### 4.3 Service 模板

```swift
// Sources/QuiteNote/Business/Services/RecordService.swift
import Foundation
import Combine

/// 记录服务协议
///
/// 定义了记录管理的核心操作接口，
/// 包括 CRUD 操作、搜索、导入导出等功能。
protocol RecordServiceProtocol {
    /// 获取所有记录
    /// - Returns: 记录数组
    func getAllRecords() async throws -> [Record]

    /// 根据 ID 获取记录
    /// - Parameter id: 记录 ID
    /// - Returns: 记录（可能为 nil）
    func getRecord(id: UUID) async throws -> Record?

    /// 添加新记录
    /// - Parameter record: 新记录
    /// - Returns: 保存后的记录
    /// - Throws: RecordError
    func addRecord(_ record: Record) async throws -> Record

    /// 更新记录
    /// - Parameter record: 要更新的记录
    /// - Returns: 更新后的记录
    /// - Throws: RecordError
    func updateRecord(_ record: Record) async throws -> Record

    /// 删除记录
    /// - Parameter id: 记录 ID
    /// - Throws: RecordError
    func deleteRecord(id: UUID) async throws

    /// 删除所有记录
    /// - Throws: RecordError
    func deleteAllRecords() async throws

    /// 搜索记录
    /// - Parameters:
    ///   - query: 搜索查询
    ///   - options: 搜索选项
    /// - Returns: 匹配的记录数组
    func searchRecords(query: String, options: SearchOptions) async throws -> [Record]

    /// 导出记录
    /// - Parameters:
    ///   - format: 导出格式
    ///   - records: 要导出的记录
    /// - Returns: 导出文件的 URL
    /// - Throws: ExportError
    func exportRecords(format: ExportFormat, records: [Record]) async throws -> URL

    /// 导入记录
    /// - Parameter url: 导入文件的 URL
    /// - Returns: 导入的记录数组
    /// - Throws: ImportError
    func importRecords(from url: URL) async throws -> [Record]

    /// 获取统计信息
    /// - Returns: 统计信息
    func getStatistics() async -> RecordStatistics
}

/// 记录服务实现
///
/// 提供记录管理的具体实现，协调 Repository、
/// Search Service、AI Service 等组件完成业务逻辑。
@MainActor
final class RecordServiceImpl: RecordServiceProtocol {
    // MARK: - Properties

    private let repository: RecordRepositoryProtocol
    private let searchService: SearchServiceProtocol
    private let aiService: AIServiceProtocol?
    private let logger: LoggerProtocol

    // MARK: - Init

    /// 初始化 RecordServiceImpl
    /// - Parameters:
    ///   - repository: 记录仓库
    ///   - searchService: 搜索服务
    ///   - aiService: AI 服务（可选）
    ///   - logger: 日志服务
    init(
        repository: RecordRepositoryProtocol,
        searchService: SearchServiceProtocol,
        aiService: AIServiceProtocol? = nil,
        logger: LoggerProtocol
    ) {
        self.repository = repository
        self.searchService = searchService
        self.aiService = aiService
        self.logger = logger
    }

    // MARK: - RecordServiceProtocol

    func getAllRecords() async throws -> [Record] {
        logger.debug("Fetching all records")

        do {
            let records = try await repository.getAll()
            logger.info("Retrieved \(records.count) records")
            return records
        } catch {
            logger.error("Failed to fetch records: \(error)")
            throw RecordError.fetchFailed(error)
        }
    }

    func getRecord(id: UUID) async throws -> Record? {
        logger.debug("Fetching record with ID: \(id)")

        do {
            let record = try await repository.get(id: id)
            if let record = record {
                logger.debug("Found record: \(record.title)")
            } else {
                logger.debug("Record not found: \(id)")
            }
            return record
        } catch {
            logger.error("Failed to fetch record \(id): \(error)")
            throw RecordError.fetchFailed(error)
        }
    }

    func addRecord(_ record: Record) async throws -> Record {
        logger.info("Adding new record: \(record.title)")

        // 1. 验证记录
        guard await !isDuplicate(record) else {
            logger.warning("Duplicate record detected: \(record.title)")
            throw RecordError.duplicateRecord
        }

        // 2. AI 处理（如果启用）
        var processedRecord = record
        if let aiService = aiService, SettingsManager.shared.enableAIProcessing {
            do {
                let summary = try await aiService.summarize(
                    text: record.content,
                    options: AISummaryOptions(
                        maxTokens: 200,
                        temperature: 0.7
                    )
                )
                processedRecord.aiSummary = summary
                processedRecord.isAIProcessed = true
                processedRecord.aiProvider = aiService.currentProvider.name
                logger.debug("AI processing completed for: \(record.title)")
            } catch {
                logger.warning("AI processing failed for \(record.title): \(error)")
                // AI 处理失败不影响记录保存
            }
        }

        // 3. 保存记录
        do {
            let savedRecord = try await repository.save(processedRecord)
            logger.info("Record saved successfully: \(savedRecord.id)")
            return savedRecord
        } catch {
            logger.error("Failed to save record: \(error)")
            throw RecordError.saveFailed(error)
        }
    }

    func updateRecord(_ record: Record) async throws -> Record {
        logger.info("Updating record: \(record.id)")

        guard let existingRecord = try await repository.get(id: record.id) else {
            throw RecordError.recordNotFound
        }

        let updatedRecord = Record(
            id: existingRecord.id,
            title: record.title,
            content: record.content,
            timestamp: Date(),
            sha1: record.sha1,
            isStarred: record.isStarred,
            aiSummary: record.aiSummary,
            isAIProcessed: record.isAIProcessed,
            aiProvider: record.aiProvider
        )

        do {
            let savedRecord = try await repository.save(updatedRecord)
            logger.info("Record updated: \(savedRecord.id)")
            return savedRecord
        } catch {
            logger.error("Failed to update record \(record.id): \(error)")
            throw RecordError.saveFailed(error)
        }
    }

    func deleteRecord(id: UUID) async throws {
        logger.info("Deleting record: \(id)")

        guard let record = try await repository.get(id: id) else {
            throw RecordError.recordNotFound
        }

        do {
            try await repository.delete(id: id)
            logger.info("Record deleted: \(id)")
        } catch {
            logger.error("Failed to delete record \(id): \(error)")
            throw RecordError.deleteFailed(error)
        }
    }

    func deleteAllRecords() async throws {
        logger.warning("Deleting all records")

        do {
            try await repository.deleteAll()
            logger.info("All records deleted")
        } catch {
            logger.error("Failed to delete all records: \(error)")
            throw RecordError.deleteFailed(error)
        }
    }

    func searchRecords(query: String, options: SearchOptions) async throws -> [Record] {
        logger.debug("Searching records with query: \(query)")

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        do {
            let results = try await searchService.search(query: query, options: options)
            logger.info("Search completed, found \(results.count) results")
            return results
        } catch {
            logger.error("Search failed: \(error)")
            throw RecordError.searchFailed(error)
        }
    }

    func exportRecords(format: ExportFormat, records: [Record]) async throws -> URL {
        logger.info("Exporting \(records.count) records to format: \(format)")

        let exporter = RecordExporter(format: format)
        do {
            let url = try await exporter.export(records: records)
            logger.info("Export completed: \(url)")
            return url
        } catch {
            logger.error("Export failed: \(error)")
            throw RecordError.exportFailed(error)
        }
    }

    func importRecords(from url: URL) async throws -> [Record] {
        logger.info("Importing records from: \(url)")

        let importer = RecordImporter()
        do {
            let records = try await importer.import(from: url)
            logger.info("Import completed, \(records.count) records imported")
            return records
        } catch {
            logger.error("Import failed: \(error)")
            throw RecordError.importFailed(error)
        }
    }

    func getStatistics() async -> RecordStatistics {
        logger.debug("Calculating statistics")

        do {
            let allRecords = try await repository.getAll()
            let totalRecords = allRecords.count
            let starredRecords = allRecords.filter { $0.isStarred }.count
            let aiProcessedRecords = allRecords.filter { $0.isAIProcessed }.count

            let today = Calendar.current.startOfDay(for: Date())
            let thisWeek = Calendar.current.date(
                byAdding: .day,
                value: -Calendar.current.component(.weekday, from: Date()) + 1,
                to: today
            )!
            let thisMonth = Calendar.current.date(
                byAdding: .day,
                value: -Calendar.current.component(.day, from: today) + 1,
                to: today
            )!

            let todayRecords = allRecords.filter {
                Calendar.current.isDate($0.timestamp, inSameDayAs: today)
            }.count

            let thisWeekRecords = allRecords.filter {
                $0.timestamp >= thisWeek
            }.count

            let thisMonthRecords = allRecords.filter {
                $0.timestamp >= thisMonth
            }.count

            return RecordStatistics(
                totalRecords: totalRecords,
                starredRecords: starredRecords,
                aiProcessedRecords: aiProcessedRecords,
                todayRecords: todayRecords,
                thisWeekRecords: thisWeekRecords,
                thisMonthRecords: thisMonthRecords
            )
        } catch {
            logger.error("Failed to calculate statistics: \(error)")
            return RecordStatistics.empty
        }
    }

    // MARK: - Private Methods

    private func isDuplicate(_ record: Record) async -> Bool {
        do {
            let existingRecords = try await repository.find(bySHA1: record.sha1)
            return !existingRecords.isEmpty
        } catch {
            logger.error("Failed to check for duplicates: \(error)")
            return false
        }
    }
}

// MARK: - Error Types
enum RecordError: Error, LocalizedError {
    case fetchFailed(Error)
    case saveFailed(Error)
    case deleteFailed(Error)
    case recordNotFound
    case duplicateRecord
    case searchFailed(Error)
    case exportFailed(Error)
    case importFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let error):
            return "获取记录失败: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "保存记录失败: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "删除记录失败: \(error.localizedDescription)"
        case .recordNotFound:
            return "记录不存在"
        case .duplicateRecord:
            return "记录已存在"
        case .searchFailed(let error):
            return "搜索失败: \(error.localizedDescription)"
        case .exportFailed(let error):
            return "导出失败: \(error.localizedDescription)"
        case .importFailed(let error):
            return "导入失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - Data Types
struct SearchOptions {
    let includeContent: Bool
    let includeTitle: Bool
    let includeAI: Bool
    let dateRange: DateRange?
    let tags: [String]?

    static let `default` = SearchOptions(
        includeContent: true,
        includeTitle: true,
        includeAI: true,
        dateRange: nil,
        tags: nil
    )
}

struct DateRange {
    let start: Date
    let end: Date
}

struct RecordStatistics {
    let totalRecords: Int
    let starredRecords: Int
    let aiProcessedRecords: Int
    let todayRecords: Int
    let thisWeekRecords: Int
    let thisMonthRecords: Int

    static let empty = RecordStatistics(
        totalRecords: 0,
        starredRecords: 0,
        aiProcessedRecords: 0,
        todayRecords: 0,
        thisWeekRecords: 0,
        thisMonthRecords: 0
    )
}
```

---

## 5. 实施计划

### 5.1 阶段一：基础架构（1-2 周）

**目标**：建立新的文件结构和基础架构

**任务**：
1. ✅ 创建新的目录结构
2. ✅ 迁移主题系统
3. ✅ 创建 Service Container 和依赖注入
4. ✅ 迁移核心数据模型
5. ✅ 迁移 Core Data 层

**里程碑**：
- 新的文件结构建立完成
- 基础的依赖注入可以工作
- 应用可以启动（可能有部分功能缺失）

### 5.2 阶段二：业务层重构（2-3 周）

**目标**：重构业务逻辑层

**任务**：
1. 重构 RecordService（从 RecordStore）
2. 创建 ViewModel 层
3. 重构 AI 服务
4. 重构设备连接服务
5. 创建状态管理

**里程碑**：
- 业务逻辑清晰分离
- ViewModel 模式正常工作
- 服务层可以独立测试

### 5.3 阶段三：表现层重构（2-3 周）

**目标**：重构用户界面

**任务**：
1. 重构悬浮窗界面
2. 重构设置界面
3. 创建组件库
4. 统一主题应用
5. 优化用户体验

**里程碑**：
- 新的 UI 架构完成
- 组件可复用
- 主题系统统一

### 5.4 阶段四：集成和优化（1-2 周）

**目标**：集成各层并优化

**任务**：
1. 集成各层组件
2. 性能优化
3. 错误处理完善
4. 测试覆盖
5. 文档完善

**里程碑**：
- 完整的应用功能
- 性能达标
- 测试覆盖充分

### 5.5 阶段五：验证和发布（1 周）

**目标**：验证重构效果并发布

**任务**：
1. 全面测试
2. 用户验收
3. 性能测试
4. 准备发布
5. 文档归档

**里程碑**：
- 重构完成并发布
- 团队熟悉新架构
- 文档完整

---

## 6. 验证清单

### 6.1 架构验证

- [ ] **分层清晰**：Presentation、Business、Data、Infrastructure 层次分明
- [ ] **依赖方向正确**：依赖只能从上层指向下层
- [ ] **接口抽象**：各层之间通过协议交互
- [ ] **依赖注入**：使用 Service Container 管理依赖

### 6.2 代码质量验证

- [ ] **命名规范**：遵循 Swift 命名约定
- [ ] **文档完整**：所有公共 API 有文档注释
- [ ] **错误处理**：完善的错误处理机制
- [ ] **线程安全**：UI 操作在主线程，数据操作在后台线程

### 6.3 功能验证

- [ ] **记录管理**：增删改查功能正常
- [ ] **AI 功能**：智能提炼正常工作
- [ ] **设备连接**：蓝牙功能正常
- [ ] **设置功能**：偏好设置正常
- [ ] **搜索功能**：全文搜索正常
- [ ] **导出功能**：数据导出正常

### 6.4 性能验证

- [ ] **启动时间**：应用启动时间 < 3 秒
- [ ] **响应时间**：UI 操作响应时间 < 100ms
- [ ] **内存使用**：空闲时内存 < 100MB
- [ ] **电池消耗**：正常使用不影响电池续航

### 6.5 用户体验验证

- [ ] **界面一致性**：所有界面使用统一主题
- [ ] **交互流畅**：动画和过渡自然流畅
- [ ] **可访问性**：支持 VoiceOver 和键盘导航
- [ ] **响应式设计**：适配不同屏幕尺寸

### 6.6 测试验证

- [ ] **单元测试**：核心业务逻辑测试覆盖 > 80%
- [ ] **集成测试**：模块间集成测试正常
- [ ] **UI 测试**：关键用户路径测试通过
- [ ] **性能测试**：通过性能基准测试

### 6.7 文档验证

- [ ] **架构文档**：架构设计文档完整
- [ ] **API 文档**：所有公共 API 有文档
- [ ] **使用指南**：用户使用指南完整
- [ ] **开发指南**：开发者指南和最佳实践

---

## 总结

本次文件结构重新组织是一个系统性工程，目标是建立一个清晰、可维护、可扩展的代码架构。

### 核心改进

1. **清晰的分层架构**：Presentation、Business、Data、Infrastructure 四层分离
2. **模块化组织**：按功能模块组织文件，相关代码集中管理
3. **标准的文件模板**：提供统一的文件模板，确保代码风格一致
4. **完善的依赖管理**：使用 Service Container 实现依赖注入
5. **完整的文档体系**：架构文档、API 文档、使用指南一应俱全

### 预期收益

1. **提高开发效率**：清晰的架构让开发者快速定位和修改代码
2. **降低维护成本**：模块化设计降低修改的复杂度和风险
3. **提升代码质量**：统一的规范和模板保证代码质量
4. **便于团队协作**：明确的分工和规范减少协作摩擦
5. **支持快速扩展**：良好的架构支持新功能的快速添加

### 后续工作

1. **持续优化**：根据实际使用反馈持续优化架构
2. **工具支持**：开发脚本和工具辅助代码生成和检查
3. **团队培训**：确保团队成员熟悉新架构和规范
4. **代码审查**：建立基于新架构的代码审查流程
5. **文档维护**：持续维护和更新文档

通过这次重新组织，QuiteNote 将拥有一个现代化、专业化的代码架构，为项目的长期发展奠定坚实基础。

---

**文档结束**