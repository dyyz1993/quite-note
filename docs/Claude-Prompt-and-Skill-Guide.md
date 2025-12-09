# Claude Code 提示词和 Skill 规范文档

> 版本：2.0
> 日期：2025-12-09
> 作者：Claude Code

## 目录

1. [概述](#1-概述)
2. [项目上下文](#2-项目上下文)
3. [开发提示词](#3-开发提示词)
4. [代码审查提示词](#4-代码审查提示词)
5. [架构设计提示词](#5-架构设计提示词)
6. [测试提示词](#6-测试提示词)
7. [文档提示词](#7-文档提示词)
8. [Claude Skill 规范](#8-claude-skill-规范)
9. [使用指南](#9-使用指南)
10. [最佳实践](#10-最佳实践)

---

## 1. 概述

本文档为 Claude Code 提供专门的提示词和 Skill，用于高效开发和维护 QuiteNote macOS 应用。这些提示词和 Skill 基于项目的架构设计、开发规范和最佳实践制定。

### 1.1 目标

- 提供标准化的开发指导
- 确保代码质量和一致性
- 加速开发流程
- 减少常见错误
- 促进最佳实践的遵循

### 1.2 适用范围

- Swift 代码开发
- SwiftUI UI 实现
- 架构设计和重构
- 代码审查
- 测试编写
- 文档生成

---

## 2. 项目上下文

### 2.1 项目简介

**QuiteNote** 是一款 macOS 菜单栏应用，通过蓝牙硬件按钮一键采集剪贴板内容，使用 AI 进行智能提炼，并提供悬浮窗快速管理和查看。

### 2.2 核心技术栈

- **语言**：Swift 5.9+
- **UI 框架**：SwiftUI + AppKit
- **数据持久化**：Core Data
- **网络**：URLSession
- **蓝牙**：CoreBluetooth
- **安全**：Keychain
- **依赖管理**：Swift Package Manager

### 2.3 架构概览

```
表现层 (Presentation) - SwiftUI Views, ViewModels
    ↓
业务层 (Business) - Services, Managers, State
    ↓
数据层 (Data) - Repositories, Persistence, Core Data
    ↓
基础设施层 (Infrastructure) - Utils, Extensions, Platform Abstraction
```

### 2.4 设计原则

- **SOLID 原则**：单一职责、开闭原则、依赖倒置等
- **协议优先**：通过协议定义接口
- **依赖注入**：使用 Service Container 管理依赖
- **响应式编程**：使用 Combine 框架
- **线程安全**：使用 @MainActor 确保 UI 线程安全

### 2.5 主题系统

基于 Tailwind CSS 的设计系统：

```swift
// 颜色系统
Color.themeBackground    // 主背景色
Color.themeCard         // 卡片背景
Color.themeTextPrimary  // 主要文本

// 间距系统
ThemeSpacing.p4.rawValue    // 16px
ThemeSpacing.p8.rawValue    // 32px

// 字体系统
Font.themeH1    // 16pt, semibold
Font.themeBody  // 14pt, regular

// 动画系统
Animation.easeOut    // 300ms ease-out
Animation.spring     // 弹性动画
```

---

## 3. 开发提示词

### 3.1 创建新功能模块

**提示词 ID**: `create-feature-module`
**触发条件**: 当需要创建新的功能模块时

```
# 任务描述
请为 QuiteNote 应用创建一个新的功能模块。

# 模块要求
- 模块名称：[用户输入]
- 模块类型：[选择：Service/Manager/View/ViewModel/Repository]
- 主要功能：[用户描述]

# 架构要求
1. 遵循分层架构（表现层/业务层/数据层）
2. 使用协议定义接口
3. 实现依赖注入
4. 遵循 SOLID 原则

# 代码规范
1. 使用 Swift 命名约定（PascalCase for classes, camelCase for variables）
2. 添加完整的文档注释
3. 使用主题系统（Color+Theme, Font+Theme等）
4. 实现错误处理
5. 确保线程安全（使用 @MainActor）

# 输出要求
1. 创建所有必要的文件
2. 实现协议和具体类
3. 添加单元测试
4. 更新 Service Container 配置

# 示例
如果创建"通知服务"模块：
- Protocol: NotificationService
- Implementation: LocalNotificationService
- Tests: NotificationServiceTests
- Registration: ServiceContainer.configureNotifications()
```

### 3.2 实现 SwiftUI 视图

**提示词 ID**: `implement-swiftui-view`
**触发条件**: 当需要实现或修改 SwiftUI 视图时

```
# 视图实现指南

## 基本要求
1. 使用 SwiftUI 最佳实践
2. 遵循主题系统
3. 实现响应式设计
4. 支持可访问性
5. 优化性能

## 视图结构模板
```swift
import SwiftUI

/// [视图描述]
///
/// 此视图用于 [用途说明]
///
/// - Note: [注意事项]
/// - Warning: [警告信息]
struct [ViewName]View: View {
    // MARK: - Properties

    // 依赖注入
    @StateObject private var viewModel: [ViewModelName]ViewModel

    // 环境变量
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // 状态管理
    @State private var isEditing = false
    @State private var searchText = ""

    // MARK: - Init

    init(viewModel: [ViewModelName]ViewModel? = nil) {
        let vm = viewModel ?? ServiceContainer.shared.resolve()
        _viewModel = StateObject(wrappedValue: vm)
    }

    // MARK: - Body

    var body: some View {
        [Content]
            .onAppear {
                viewModel.load()
            }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var content: some View {
        // 根据状态显示不同内容
        if viewModel.isLoading {
            LoadingView()
        } else if viewModel.items.isEmpty {
            EmptyStateView()
        } else {
            listView
        }
    }

    private var listView: some View {
        List {
            ForEach(viewModel.items) { item in
                ItemRowView(item: item)
            }
            .onDelete(perform: deleteItems)
        }
    }
}

// MARK: - Previews
#preview {
    [ViewName]View()
        .preferredColorScheme(.dark)
}
```

## 主题使用
- 背景色：Color.themeBackground
- 卡片背景：Color.themeCard
- 主要文本：Color.themeTextPrimary
- 次要文本：Color.themeTextSecondary
- 边框：Color.themeBorder

## 动画规范
- 标准动画：Animation.easeOut(duration: 0.3)
- 快速动画：Animation.easeOut(duration: 0.1)
- 弹性动画：Animation.spring(response: 0.2, dampingFraction: 0.8)

## 性能优化
1. 使用 LazyVStack 而非 VStack
2. 使用 @ViewBuilder 减少视图构建
3. 实现 Equatable 减少重绘
4. 使用 .task 而非 .onAppear 处理异步操作
5. 使用 .equatable 修饰 ForEach

## 可访问性
1. 添加 accessibilityLabel
2. 支持动态字体
3. 提供足够的对比度
4. 支持键盘导航
```

### 3.3 创建数据模型

**提示词 ID**: `create-data-model`
**触发条件**: 当需要创建新的数据模型时

```
# 数据模型创建指南

## 基本要求
1. 遵循 Core Data 最佳实践
2. 实现 Codable 协议
3. 添加适当的索引
4. 实现数据验证
5. 考虑数据迁移

## 模型模板
```swift
import Foundation
import CoreData

// MARK: - Model Protocol
/// 表示 [实体名称] 的协议
protocol [ModelName]Protocol {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    // 添加业务属性
}

// MARK: - Model Struct
/// [实体描述]
///
/// 此模型用于表示 [业务概念]
/// - Note: 此结构体是值类型，用于在 UI 层传递数据
/// - SeeAlso: CD[modelName] (Core Data 实体)
struct [ModelName]: Identifiable, Codable, Equatable {
    // MARK: - Properties

    let id: UUID
    var createdAt: Date
    var updatedAt: Date

    // 业务属性
    var name: String
    var description: String?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        name: String,
        description: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.description = description
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, name, description
    }

    // MARK: - Validation

    /// 验证模型数据的有效性
    /// - Returns: 验证结果，失败时返回错误信息
    func validate() -> Result<(), Error> {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure([ModelName]Error.invalidName)
        }
        return .success(())
    }
}

// MARK: - Core Data Entity
extension CD[modelName] {
    /// 从 [ModelName] 创建 Core Data 实体
    static func from(_ model: [ModelName], context: NSManagedObjectContext) -> CD[modelName] {
        let entity = CD[modelName](context: context)
        entity.id = model.id
        entity.createdAt = model.createdAt
        entity.updatedAt = model.updatedAt
        entity.name = model.name
        entity.description = model.description
        return entity
    }

    /// 转换为 [ModelName] 结构体
    func toModel() -> [ModelName] {
        return [ModelName](
            id: id ?? UUID(),
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date(),
            name: name ?? "",
            description: description
        )
    }
}

// MARK: - Extensions
extension [ModelName] {
    /// 生成示例数据（用于预览和测试）
    static let sample = [ModelName](
        name: "Sample [ModelName]",
        description: "This is a sample [model description]"
    )

    /// 生成测试数据数组
    static let samples: [ModelName] = [
        .init(name: "Sample 1", description: "First sample"),
        .init(name: "Sample 2", description: "Second sample"),
        .init(name: "Sample 3", description: "Third sample")
    ]
}

// MARK: - Error Handling
enum [ModelName]Error: Error, LocalizedError {
    case invalidName
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Name cannot be empty"
        case .invalidData:
            return "Invalid data format"
        }
    }
}
```

## Core Data 配置
在 Core Data 模型编辑器中：
1. 创建实体 CD[modelName]
2. 添加属性（与结构体属性对应）
3. 设置索引（对经常查询的属性）
4. 配置关系（如果需要）
5. 设置级联删除（如果需要）

## 使用示例
```swift
// 创建
let newModel = [ModelName](name: "Test", description: "Test description")

// 验证
switch newModel.validate() {
case .success:
    // 保存到 Core Data
    let entity = CD[modelName].from(newModel, context: context)
    try? context.save()
case .failure(let error):
    print("Validation failed: \(error)")
}
```
```

### 3.4 实现服务类

**提示词 ID**: `implement-service`
**触发条件**: 当需要实现服务类时

```
# 服务类实现指南

## 基本要求
1. 定义清晰的协议
2. 实现依赖注入
3. 处理异步操作
4. 实现错误处理
5. 添加日志记录
6. 考虑线程安全

## 服务模板
```swift
import Foundation
import Combine

// MARK: - Service Protocol
/// [服务描述]协议
///
/// 此协议定义了 [服务功能] 的接口
/// - Note: 所有实现必须是线程安全的
protocol [ServiceName]Protocol {
    /// [方法描述]
    /// - Parameter parameter: [参数描述]
    /// - Returns: [返回值描述]
    /// - Throws: [可能抛出的错误]
    func [methodName]([parameter]: [ParameterType]) async throws -> [ReturnType]

    /// [另一个方法描述]
    /// - Parameters:
    ///   - items: [参数描述]
    ///   - options: [参数描述]
    /// - Returns: [返回值描述]
    func [anotherMethod](items: [ItemType], options: [OptionsType]) -> AnyPublisher<[ReturnType], Error>
}

// MARK: - Service Implementation
/// [服务描述]的具体实现
///
/// 此类实现了 [ServiceName]Protocol 协议，
/// 提供 [服务功能] 的具体实现。
@MainActor
final class [ServiceName]Impl: [ServiceName]Protocol {
    // MARK: - Properties

    // 依赖项
    private let networkService: NetworkServiceProtocol
    private let persistenceService: PersistenceServiceProtocol
    private let logger: LoggerProtocol

    // 状态管理
    private var isInitialized = false
    private var cache: [CacheKey: CacheValue] = [:]

    // MARK: - Init

    /// 初始化 [ServiceName]Impl
    /// - Parameters:
    ///   - networkService: 网络服务依赖
    ///   - persistenceService: 持久化服务依赖
    ///   - logger: 日志服务依赖
    init(
        networkService: NetworkServiceProtocol,
        persistenceService: PersistenceServiceProtocol,
        logger: LoggerProtocol
    ) {
        self.networkService = networkService
        self.persistenceService = persistenceService
        self.logger = logger
    }

    // MARK: - [ServiceName]Protocol

    func [methodName]([parameter]: [ParameterType]) async throws -> [ReturnType] {
        // 1. 参数验证
        guard [validationCondition] else {
            throw [ServiceName]Error.invalidParameter
        }

        // 2. 检查缓存
        if let cached = cache[[cacheKey]] {
            logger.debug("Cache hit for [methodName]")
            return cached
        }

        // 3. 执行业务逻辑
        do {
            let result = try await execute[MethodName]([parameter]: [parameter])

            // 4. 缓存结果
            cache[[cacheKey]] = result

            // 5. 记录日志
            logger.info("[methodName] completed successfully")

            return result
        } catch {
            // 6. 错误处理
            logger.error("[methodName] failed: \(error)")
            throw error
        }
    }

    func [anotherMethod](items: [ItemType], options: [OptionsType]) -> AnyPublisher<[ReturnType], Error> {
        return Future<[ReturnType], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure([ServiceName]Error.serviceDeinitialized))
                return
            }

            Task {
                do {
                    let result = try await self.processItems(items, with: options)
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    // MARK: - Private Methods

    @MainActor
    private func execute[MethodName]([parameter]: [ParameterType]) async throws -> [ReturnType] {
        // 具体实现逻辑
        // 注意：此方法在 MainActor 中执行
    }

    private func processItems(_ items: [ItemType], with options: [OptionsType]) async throws -> [ReturnType] {
        // 处理项目列表
        // 注意：此方法不在 MainActor 中执行
    }

    private func validate[Parameter](_ parameter: [ParameterType]) throws {
        // 参数验证逻辑
    }

    private func [cacheKey](_ parameter: [ParameterType]) -> CacheKey {
        // 生成缓存键
    }
}

// MARK: - Error Handling
enum [ServiceName]Error: Error, LocalizedError {
    case invalidParameter
    case networkError
    case persistenceError
    case serviceDeinitialized

    var errorDescription: String? {
        switch self {
        case .invalidParameter:
            return "Invalid parameter provided"
        case .networkError:
            return "Network request failed"
        case .persistenceError:
            return "Data persistence failed"
        case .serviceDeinitialized:
            return "Service was deinitialized"
        }
    }
}

// MARK: - Service Registration
extension ServiceContainer {
    /// 配置 [ServiceName] 服务
    func configure[ServiceName]() {
        register([ServiceName]Protocol.self) {
            [ServiceName]Impl(
                networkService: resolve() as NetworkServiceProtocol,
                persistenceService: resolve() as PersistenceServiceProtocol,
                logger: resolve() as LoggerProtocol
            )
        }
    }
}
```

## 使用示例
```swift
// 在 ServiceContainer.configure() 中调用
ServiceContainer.shared.configure[ServiceName]()

// 在需要的地方使用
let service = ServiceContainer.shared.resolve() as [ServiceName]Protocol
Task {
    do {
        let result = try await service.[methodName]([parameter])
        // 处理结果
    } catch {
        // 处理错误
    }
}
```

## 最佳实践
1. **单一职责**：每个服务只负责一个特定的业务领域
2. **依赖倒置**：依赖抽象而非具体实现
3. **错误处理**：提供清晰的错误信息
4. **日志记录**：记录关键操作和错误
5. **缓存策略**：合理使用缓存提升性能
6. **线程安全**：使用 @MainActor 确保 UI 相关操作在主线程执行
```

---

## 4. 代码审查提示词

### 4.1 通用代码审查

**提示词 ID**: `code-review-general`
**触发条件**: 当需要审查代码时

```
# 代码审查指南

请对以下代码进行全面审查：

## 审查清单

### 1. 架构和设计
- [ ] 是否遵循分层架构？
- [ ] 是否使用了协议而非具体实现？
- [ ] 依赖注入是否正确实现？
- [ ] 是否遵循 SOLID 原则？

### 2. 代码质量
- [ ] 代码是否清晰易懂？
- [ ] 变量和函数命名是否恰当？
- [ ] 是否有重复代码？
- [ ] 函数是否过长（超过 50 行）？

### 3. Swift 最佳实践
- [ ] 是否正确使用可选类型？
- [ ] 是否避免了强制解包？
- [ ] 是否正确使用了 weak/unowned？
- [ ] 错误处理是否恰当？

### 4. 性能
- [ ] 是否有性能问题？
- [ ] 是否有内存泄漏风险？
- [ ] 是否使用了合适的集合类型？
- [ ] 异步操作是否正确实现？

### 5. 安全性
- [ ] 是否有安全漏洞？
- [ ] 敏感数据是否得到保护？
- [ ] 输入是否得到验证？

### 6. 可测试性
- [ ] 代码是否易于测试？
- [ ] 是否使用了依赖注入？
- [ ] 是否有适当的抽象？

### 7. 文档和注释
- [ ] 是否有适当的文档注释？
- [ ] 复杂逻辑是否有解释？
- [ ] 是否遵循文档规范？

### 8. 主题和 UI
- [ ] 是否使用了主题系统？
- [ ] 是否遵循 UI 规范？
- [ ] 是否支持可访问性？
- [ ] 是否有硬编码的颜色或尺寸？

## 审查输出格式

### 发现的问题：

1. **[严重性：高/中/低] [类型：架构/代码/性能/安全/其他]**
   - **位置**：文件名:行号
   - **问题描述**：
   - **建议修复**：

2. **[严重性：高/中/低] [类型：架构/代码/性能/安全/其他]**
   - **位置**：文件名:行号
   - **问题描述**：
   - **建议修复**：

### 优点：

1. [列出代码的优点]

### 总体评价：

[对代码的整体评价和改进建议]
```

### 4.2 SwiftUI 视图审查

**提示词 ID**: `code-review-swiftui`
**触发条件**: 当需要审查 SwiftUI 视图时

```
# SwiftUI 视图代码审查

请对以下 SwiftUI 视图代码进行专门审查：

## 审查重点

### 1. SwiftUI 最佳实践
- [ ] 是否使用了合适的视图修饰符？
- [ ] 状态管理是否正确？
- [ ] 是否正确使用了 @StateObject 和 @ObservedObject？
- [ ] 视图层次是否合理？

### 2. 性能优化
- [ ] 是否使用了 LazyVStack/LazyHStack？
- [ ] ForEach 是否有正确的 id？
- [ ] 是否避免了在 body 中进行复杂计算？
- [ ] 是否使用了 @ViewBuilder？

### 3. 响应式设计
- [ ] 是否适应不同屏幕尺寸？
- [ ] 是否使用了 GeometryReader？
- [ ] 是否有硬编码的尺寸？

### 4. 主题系统
- [ ] 是否使用了 Color.theme*？
- [ ] 是否使用了 Font.theme*？
- [ ] 是否使用了 ThemeSpacing？
- [ ] 是否使用了主题动画？

### 5. 可访问性
- [ ] 是否添加了 accessibilityLabel？
- [ ] 是否支持动态字体？
- [ ] 对比度是否足够？
- [ ] 点击区域是否足够大？

### 6. 代码组织
- [ ] 是否使用了 @ViewBuilder 分解复杂视图？
- [ ] 是否有清晰的注释分隔？
- [ ] 属性是否按逻辑分组？

## 审查输出格式

### SwiftUI 特有问题：

1. **[严重性：高/中/低]**
   - **位置**：文件名:行号
   - **问题**：
   - **SwiftUI 最佳实践建议**：

### 改进建议：

1. **性能优化建议**：
   - [具体建议]

2. **可访问性改进**：
   - [具体建议]

3. **主题系统使用**：
   - [具体建议]

4. **代码组织**：
   - [具体建议]
```

---

## 5. 架构设计提示词

### 5.1 架构评估

**提示词 ID**: `architecture-review`
**触发条件**: 当需要评估或设计架构时

```
# 架构设计和评估指南

## 架构原则检查

### 1. 分层架构
请评估以下架构是否符合分层要求：

```
表现层 (Presentation) - Views, ViewModels
    ↓
业务层 (Business) - Services, Managers
    ↓
数据层 (Data) - Repositories, Core Data
    ↓
基础设施层 (Infrastructure) - Utils, Extensions
```

**检查点**：
- [ ] 层与层之间是否有清晰的边界？
- [ ] 是否存在跨层依赖？
- [ ] 每一层的职责是否明确？

### 2. 依赖管理
评估依赖注入的实现：

**检查点**：
- [ ] 是否使用了协议而非具体实现？
- [ ] Service Container 设计是否合理？
- [ ] 是否存在循环依赖？

### 3. 可扩展性
评估架构的可扩展性：

**检查点**：
- [ ] 添加新功能是否容易？
- [ ] 修改现有功能是否影响其他模块？
- [ ] 是否支持插件化？

### 4. 可维护性
评估代码的可维护性：

**检查点**：
- [ ] 代码是否易于理解？
- [ ] 模块间耦合度是否低？
- [ ] 是否有清晰的文档？

### 5. 性能考虑
评估架构的性能：

**检查点**：
- [ ] 是否有性能瓶颈？
- [ ] 数据流是否高效？
- [ ] 内存使用是否合理？

## 架构改进建议

基于以上评估，请提供：

1. **架构图改进**：
   [建议的架构图或文字描述]

2. **关键改进点**：
   - [改进点 1]
   - [改进点 2]

3. **实施计划**：
   - 短期（1-2 周）：
   - 中期（1-2 月）：
   - 长期（3-6 月）：

4. **风险评估**：
   - [潜在风险和缓解措施]
```

### 5.2 模块设计

**提示词 ID**: `module-design`
**触发条件**: 当需要设计新模块时

```
# 模块设计指南

请为以下需求设计模块：

## 需求描述
[用户提供的需求]

## 设计要求

### 1. 模块边界
定义模块的职责和边界：

**核心职责**：
- [职责 1]
- [职责 2]

**边界定义**：
- 与哪些模块交互
- 提供什么接口
- 依赖什么服务

### 2. 接口设计
设计清晰的接口：

```swift
protocol [ModuleName]Protocol {
    // 主要方法
    func [primaryMethod]([parameters]) async throws -> [ReturnType]

    // 次要方法
    func [secondaryMethod]([parameters]) -> AnyPublisher<[ReturnType], Error>
}
```

### 3. 类图设计
绘制类之间的关系：

```
[ModuleImpl] --|> [ModuleProtocol]
    |
    |-- [Dependency1]
    |-- [Dependency2]
    |-- [UtilityClass]
```

### 4. 数据流设计
描述数据在模块中的流动：

```
输入 -> 验证 -> 处理 -> 输出
```

### 5. 错误处理
设计统一的错误处理：

```swift
enum [ModuleError]: Error {
    case invalidInput
    case processingFailed
    case dependencyError
}
```

## 输出要求

请提供：

1. **模块架构图**
2. **接口定义**
3. **类图**
4. **数据流图**
5. **错误处理策略**
6. **测试策略**
```

---

## 6. 测试提示词

### 6.1 单元测试编写

**提示词 ID**: `write-unit-tests`
**触发条件**: 当需要为代码编写单元测试时

```
# 单元测试编写指南

请为以下代码编写完整的单元测试：

## 测试要求

### 1. 测试覆盖率
确保覆盖以下场景：

- [ ] 正常流程测试
- [ ] 边界条件测试
- [ ] 错误处理测试
- [ ] 异常情况测试

### 2. 测试结构
遵循以下测试结构：

```swift
import XCTest
@testable import QuiteNote

final class [ClassName]Tests: XCTestCase {
    // MARK: - Properties
    private var sut: [ClassName]!
    private var mockDependency1: MockDependency1!
    private var mockDependency2: MockDependency2!

    // MARK: - Lifecycle
    override func setUp() {
        super.setUp()
        // 设置测试依赖
    }

    override func tearDown() {
        // 清理资源
        sut = nil
        mockDependency1 = nil
        mockDependency2 = nil
        super.tearDown()
    }

    // MARK: - Tests
    func test_[method]_with[condition]_should[expectedBehavior]() async throws {
        // Given
        let input = [testData]

        // When
        let result = try await sut.[method](input)

        // Then
        XCTAssertEqual(result, [expectedResult])
        XCTAssertTrue([verification])
    }

    func test_[method]_with[errorCondition]_should[throwError]() async throws {
        // Given
        let input = [errorTestData]

        // When & Then
        await XCTAssertThrowsError(
            try await sut.[method](input)
        ) { error in
            XCTAssertEqual(error as? ExpectedError, .expectedErrorType)
        }
    }
}

// MARK: - Mock Classes
private class MockDependency1: Dependency1Protocol {
    // 实现 mock 方法
}
```

### 3. 测试命名
遵循以下命名约定：

- 测试方法名应该描述被测试的行为
- 格式：test_[方法名]_with[条件]_should[预期结果]
- 例如：test_calculateTotal_withValidItems_shouldReturnCorrectSum

### 4. 测试数据
使用有意义的测试数据：

- 使用真实场景的数据
- 包含边界值
- 包含无效数据

### 5. Mock 对象
正确实现 Mock 对象：

- 实现所有协议方法
- 跟踪方法调用
- 支持自定义返回值
- 验证调用次数

## 输出要求

请生成：

1. **完整的测试文件**
2. **Mock 类实现**
3. **测试数据**
4. **测试说明文档**

## 测试示例

```swift
// 示例：测试 RecordService
func test_addRecord_withValidData_shouldSaveSuccessfully() async throws {
    // Given
    let record = Record(content: "Test content", timestamp: Date())
    mockRepository.stubSave(toReturn: record)

    // When
    let savedRecord = try await sut.addRecord(record)

    // Then
    XCTAssertTrue(mockRepository.saveCalled)
    XCTAssertEqual(savedRecord.content, record.content)
}
```
```

### 6.2 UI 测试编写

**提示词 ID**: `write-ui-tests`
**触发条件**: 当需要编写 UI 测试时

```
# UI 测试编写指南

请为以下 SwiftUI 视图编写 UI 测试：

## 测试要求

### 1. 测试框架
使用 ViewInspector 进行 SwiftUI 视图测试：

```swift
import XCTest
import SwiftUI
import ViewInspector
@testable import QuiteNote

extension TargetView: Inspectable { }

final class TargetViewTests: XCTestCase {
    func test_[element]_when[condition]_should[expectedBehavior]() throws {
        // Given
        let viewModel = MockViewModel()
        let view = TargetView(viewModel: viewModel)

        // When
        let element = try view.inspect().[elementPath]()

        // Then
        XCTAssertTrue(element.exists)
        XCTAssertEqual(try element.[property](), [expectedValue])
    }
}
```

### 2. 测试场景
覆盖以下测试场景：

- [ ] 视图存在性测试
- [ ] 视图状态测试
- [ ] 用户交互测试
- [ ] 数据绑定测试
- [ ] 导航测试

### 3. 视图结构测试
验证视图层次结构：

```swift
func test_viewStructure_shouldHaveCorrectHierarchy() throws {
    let view = TargetView()

    let hierarchy = try view.inspect().[hierarchyPath]()
    XCTAssertTrue(hierarchy.exists)
}
```

### 4. 状态测试
验证视图状态变化：

```swift
func test_stateChange_shouldUpdateView() throws {
    let viewModel = MockViewModel()
    let view = TargetView(viewModel: viewModel)

    // 更改状态
    viewModel.isLoading = true

    // 验证视图更新
    let loadingView = try view.inspect().find(viewWithId: "loading")
    XCTAssertTrue(loadingView.exists)
}
```

### 5. 交互测试
验证用户交互：

```swift
func test_buttonTap_shouldExecuteAction() throws {
    var actionExecuted = false
    let button = Button("Tap me") {
        actionExecuted = true
    }

    try button.inspect().button().tap()
    XCTAssertTrue(actionExecuted)
}
```

## 输出要求

请生成：

1. **完整的 UI 测试文件**
2. **Mock ViewModel 实现**
3. **测试用例说明**
4. **预期的视图结构**

## 最佳实践

1. **测试独立性**：每个测试应该是独立的
2. **明确的断言**：测试应该有明确的通过/失败条件
3. **有意义的测试数据**：使用真实的测试数据
4. **完整的覆盖**：覆盖主要的用户交互路径
```

---

## 7. 文档提示词

### 7.1 API 文档生成

**提示词 ID**: `generate-api-docs`
**触发条件**: 当需要生成 API 文档时

```
# API 文档生成指南

请为以下代码生成完整的 API 文档：

## 文档要求

### 1. 代码注释
确保所有公共 API 都有完整的文档注释：

```swift
/// [简短描述 - 1-2 句话]
///
/// [详细描述 - 可选，说明用途、工作原理等]
///
/// # Example
/// ```swift
/// let service = MyService()
/// let result = try await service.process(data)
/// ```
///
/// - Note: [重要说明]
/// - Warning: [警告信息]
/// - SeeAlso: [相关类型或方法的链接]
///
/// - Parameters:
///   - parameter1: [参数1的描述]
///   - parameter2: [参数2的描述]
///
/// - Returns: [返回值的描述]
///
/// - Throws:
///   - MyError.invalidInput: 当输入无效时
///   - MyError.networkError: 当网络请求失败时
public func myFunction(parameter1: String, parameter2: Int) throws -> Result {
    // 实现
}
```

### 2. 文档结构
生成以下文档：

#### 2.1 类/结构体文档
- 类的用途和职责
- 主要属性和方法
- 使用示例
- 注意事项

#### 2.2 方法文档
- 方法的功能描述
- 参数说明
- 返回值说明
- 可能抛出的错误
- 使用示例

#### 2.3 属性文档
- 属性的用途
- 数据类型
- 取值范围
- 使用场景

### 3. Markdown 文档
生成以下 Markdown 文档：

#### 3.1 API 概览
```
# [模块名称] API 文档

## 概述
[模块的简要描述]

## 快速开始
```swift
// 基本使用示例
```

## API 参考

### 类和结构体

#### [ClassName]
[类的描述]

##### 属性
- `property1`: [描述]
- `property2`: [描述]

##### 方法
- `method1()`: [描述]
- `method2()`: [描述]

### 协议

#### [ProtocolName]
[协议的描述]

##### 要求
- `requiredMethod()`: [描述]
- `requiredProperty`: [描述]
```

#### 3.2 使用指南
```
# [功能名称] 使用指南

## 基本用法
[基本使用示例和说明]

## 高级用法
[高级功能的使用方法]

## 最佳实践
[推荐的使用方式和注意事项]

## 常见问题
[常见问题和解决方案]
```

## 输出格式

请生成：

1. **更新后的代码**（包含完整的文档注释）
2. **API 参考文档**（Markdown 格式）
3. **使用指南**（Markdown 格式）
4. **示例代码**

## 示例输出

```swift
/// 记录服务
///
/// 此服务负责管理记录的 CRUD 操作，
/// 包括创建、读取、更新和删除记录。
///
/// # Example
/// ```swift
/// let service = RecordService(
///     repository: CoreDataRepository(),
///     aiService: OpenAIService()
/// )
/// let record = try await service.addRecord(content: "New record")
/// ```
@MainActor
final class RecordService {
    /// 添加新记录
    ///
    /// 此方法验证记录内容，处理 AI 分析（如果启用），
    /// 并将记录保存到存储库中。
    ///
    /// - Parameter content: 记录内容，不能为空
    ///
    /// - Returns: 保存的记录，包含额外的元数据
    ///
    /// - Throws:
    ///   - RecordError.invalidContent: 当内容为空时
    ///   - RecordError.processingFailed: 当 AI 处理失败时
    ///   - RecordError.saveFailed: 当保存到存储库失败时
    ///
    /// - Note: 此方法在 Main Actor 中执行
    /// - SeeAlso: `Record`
    /// - SeeAlso: `RecordError`
    public func addRecord(content: String) async throws -> Record {
        // 实现
    }
}
```
```

### 7.2 CHANGELOG 生成

**提示词 ID**: `generate-changelog`
**触发条件**: 当需要生成 CHANGELOG 时

```
# CHANGELOG 生成指南

请基于以下 Git 提交生成 CHANGELOG：

## 生成要求

### 1. 提交分析
分析所有相关的 Git 提交，按类型分类：

- **feat**: 新功能
- **fix**: 修复 bug
- **docs**: 文档更新
- **style**: 代码格式调整
- **refactor**: 重构
- **test**: 测试相关
- **chore**: 构建过程或辅助工具的变动

### 2. CHANGELOG 格式
使用以下格式：

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [版本号] - [YYYY-MM-DD]

### Added
- 新增的功能
- 新增的 API

### Changed
- 修改的功能
- API 变更

### Deprecated
- 已弃用的功能
- 未来版本中将移除

### Removed
- 移除的功能
- 已弃用功能的移除

### Fixed
- 修复的 bug
- 性能改进

### Security
- 安全相关更新

### Breaking Changes
- 破坏性变更
- 升级指南
```

### 3. 版本号管理
遵循语义化版本控制：

- **主版本号**：当你做了不兼容的 API 修改
- **次版本号**：当你做了向下兼容的功能性新增
- **修订号**：当你做了向下兼容的问题修正

### 4. 提交信息规范化
如果提交信息不规范，请重新整理：

```
# 不规范的提交
- "update"
- "fix bug"
- "stuff"

# 规范的提交
- "feat(api): add user authentication"
- "fix(ui): resolve button alignment issue"
- "docs(readme): update installation guide"
```

## 输出要求

请生成：

1. **完整的 CHANGELOG.md**
2. **版本升级说明**
3. **破坏性变更列表**
4. **升级指南**

## 示例输出

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-12-09

### Added
- feat(ui): add dark mode toggle
- feat(api): implement record search functionality
- feat(core): add AI summary feature

### Changed
- refactor(ui): reorganize settings view layout
- refactor(core): improve performance of record processing

### Fixed
- fix(ui): resolve button alignment issue
- fix(api): handle null values in API responses
- fix(core): fix memory leak in record service

### Breaking Changes
- refactor(api): changed Record struct fields
  - `text` renamed to `content`
  - `dateCreated` renamed to `timestamp`
- refactor(ui): removed deprecated ButtonStyle

## [1.1.0] - 2025-11-15

### Added
- feat(ui): add loading states
- feat(core): add data validation

### Fixed
- fix(ui): improve error messages
- fix(core): resolve crash on startup

## [1.0.0] - 2025-10-01

### Added
- Initial release
- Core functionality
- User authentication
- Record management
```
```

---

## 8. Claude Skill 规范

### 8.1 Skill 定义

```
Skill Name: QuiteNote Developer Assistant
Skill ID: quite-note-dev-assistant
Version: 2.0
Author: Claude Code
Description: 专门用于开发和维护 QuiteNote macOS 应用的 AI 助手

## Capabilities
- 代码生成和审查
- 架构设计和评估
- 测试编写
- 文档生成
- 问题诊断和解决
- 最佳实践指导

## Context
- 项目类型：macOS 菜单栏应用
- 技术栈：Swift + SwiftUI + Core Data
- 架构：分层架构 + 依赖注入
- 设计原则：SOLID + 协议优先
- 主题系统：Tailwind 风格设计系统

## Guidelines
1. 始终遵循项目的架构和设计原则
2. 使用主题系统而非硬编码值
3. 优先使用协议和依赖注入
4. 确保代码的可测试性
5. 添加适当的文档注释
6. 考虑线程安全（@MainActor）
7. 实现完整的错误处理
8. 优化性能和用户体验
```

### 8.2 Skill 使用示例

#### 8.2.1 代码生成 Skill

```
Skill: generate-code
Trigger: "请为 QuiteNote 生成 [功能描述] 的代码"
Input Parameters:
- feature: 功能描述
- type: 代码类型（view/service/model）
- requirements: 具体要求

Processing Steps:
1. 分析功能需求
2. 确定代码类型和架构位置
3. 检查现有代码以避免重复
4. 生成符合规范的代码
5. 添加必要的测试
6. 生成文档

Output:
- 代码文件
- 测试文件
- 文档说明
```

#### 8.2.2 代码审查 Skill

```
Skill: code-review
Trigger: "请审查以下代码"
Input Parameters:
- code: 需要审查的代码
- type: 代码类型（general/swiftui/api）

Processing Steps:
1. 解析代码结构
2. 应用相应的审查清单
3. 识别潜在问题
4. 提供改进建议
5. 生成审查报告

Output:
- 审查报告
- 问题列表
- 改进建议
```

#### 8.2.3 架构设计 Skill

```
Skill: architecture-design
Trigger: "请为 [需求] 设计架构"
Input Parameters:
- requirement: 需求描述
- constraints: 约束条件

Processing Steps:
1. 分析需求
2. 评估现有架构
3. 设计新模块或改进
4. 绘制架构图
5. 定义接口和依赖

Output:
- 架构设计文档
- 类图
- 数据流图
- 接口定义
```

### 8.3 Skill 执行流程

```
# Skill 执行流程图

用户输入 → Skill 识别 → 上下文分析 → 任务分解 → 代码生成/分析 → 质量检查 → 输出结果

## 详细步骤

### 1. Skill 识别
- 分析用户输入
- 确定触发的 Skill
- 提取输入参数

### 2. 上下文分析
- 获取项目上下文
- 检查相关代码
- 确定约束条件

### 3. 任务分解
- 将任务分解为子任务
- 确定执行顺序
- 分配资源

### 4. 执行
- 生成代码或分析结果
- 应用最佳实践
- 确保质量标准

### 5. 质量检查
- 语法检查
- 逻辑验证
- 规范符合性检查

### 6. 输出
- 格式化结果
- 生成说明文档
- 提供使用指导
```

### 8.4 Skill 配置

```
# .claude/skills/quite-note-dev-assistant.json

{
  "name": "QuiteNote Developer Assistant",
  "version": "2.0",
  "description": "专门用于开发和维护 QuiteNote macOS 应用的 AI 助手",
  "triggers": [
    {
      "pattern": "请为 QuiteNote 生成",
      "skill": "generate-code",
      "description": "代码生成"
    },
    {
      "pattern": "请审查以下代码",
      "skill": "code-review",
      "description": "代码审查"
    },
    {
      "pattern": "请为 [需求] 设计架构",
      "skill": "architecture-design",
      "description": "架构设计"
    },
    {
      "pattern": "如何实现 [功能]",
      "skill": "implementation-guide",
      "description": "实现指导"
    },
    {
      "pattern": "为什么 [问题]",
      "skill": "troubleshooting",
      "description": "问题诊断"
    }
  ],
  "context": {
    "project_type": "macOS menu bar application",
    "tech_stack": ["Swift", "SwiftUI", "Core Data", "CoreBluetooth"],
    "architecture": "layered architecture with dependency injection",
    "design_principles": ["SOLID", "protocol-oriented", "MVVM"],
    "theme_system": "Tailwind CSS inspired design system"
  },
  "guidelines": [
    "Always follow project architecture and design principles",
    "Use theme system instead of hardcoded values",
    "Prefer protocols and dependency injection",
    "Ensure code testability",
    "Add appropriate documentation",
    "Consider thread safety with @MainActor",
    "Implement complete error handling",
    "Optimize performance and user experience"
  ]
}
```

---

## 9. 使用指南

### 9.1 如何使用提示词

#### 9.1.1 在 Claude Code 中使用

```bash
# 1. 打开 Claude Code
# 2. 选择项目
# 3. 使用提示词 ID 或描述

示例：
用户：请使用 "create-feature-module" 提示词创建通知服务模块
AI：正在使用 create-feature-module 提示词...

# 或者直接描述
用户：请为 QuiteNote 创建一个新的通知服务模块
AI：正在分析需求并生成代码...
```

#### 9.1.2 提示词触发方式

**方式 1：使用提示词 ID**
```
用户：请使用 "implement-swiftui-view" 提示词
AI：正在加载 implement-swiftui-view 提示词...
```

**方式 2：自然语言描述**
```
用户：我需要实现一个新的 SwiftUI 视图
AI：正在分析需求并使用相应的提示词...
```

**方式 3：结合代码**
```
用户：请审查以下代码（附上代码）
AI：正在使用 code-review 提示词审查代码...
```

### 9.2 如何使用 Skill

#### 9.2.1 Skill 自动触发

当用户输入符合 Skill 模式时，会自动触发：

```
用户：请为 QuiteNote 生成一个设置视图
→ 自动触发：generate-code Skill
```

#### 9.2.2 手动指定 Skill

```
用户：请使用 architecture-design Skill
AI：正在使用 architecture-design Skill...
```

### 9.3 最佳实践

#### 9.3.1 提供清晰的需求

```
❌ 模糊的需求
"帮我写个功能"

✅ 清晰的需求
"请为 QuiteNote 创建一个通知服务，要求：
- 支持本地通知
- 可配置通知设置
- 遵循现有的架构模式
- 包含完整的测试"
```

#### 9.3.2 指定上下文

```
"请基于当前的 RecordService 实现，创建一个类似的 NotificationService"
```

#### 9.3.3 明确期望

```
"请生成以下内容：
1. 协议定义
2. 具体实现
3. 单元测试
4. 使用示例"
```

### 9.4 常见场景

#### 9.4.1 创建新功能

```
场景：需要添加搜索功能
用户输入：
"请为 QuiteNote 添加搜索功能，要求：
- 支持全文搜索
- 按日期和标签过滤
- 显示搜索结果
- 包含搜索历史"

AI 响应：
1. 使用 architecture-design Skill 设计搜索模块
2. 使用 generate-code Skill 生成代码
3. 使用 write-unit-tests Skill 生成测试
```

#### 9.4.2 代码审查

```
场景：审查新提交的代码
用户输入：
"请审查以下 RecordService 的实现代码"

AI 响应：
1. 使用 code-review-general Skill
2. 生成审查报告
3. 提供改进建议
```

#### 9.4.3 问题诊断

```
场景：应用崩溃
用户输入：
"应用在启动时崩溃，请诊断问题"

AI 响应：
1. 使用 troubleshooting Skill
2. 分析可能的原因
3. 提供解决方案
```

---

## 10. 最佳实践

### 10.1 提示词使用最佳实践

#### 10.1.1 明确和具体

```
❌ 不好的提示
"写代码"

✅ 好的提示
"请为 QuiteNote 创建一个设置视图，包含：
- 主题切换开关
- 通知设置
- 关于页面链接
使用 SwiftUI 实现，遵循现有的设计规范"
```

#### 10.1.2 提供上下文

```
"基于现有的 RecordListViewModel，创建一个类似的 SearchResultsViewModel"
```

#### 10.1.3 分步骤请求

```
第一步：请设计搜索功能的架构
第二步：请实现搜索服务
第三步：请创建搜索界面
第四步：请编写测试
```

### 10.2 Skill 使用最佳实践

#### 10.2.1 正确触发 Skill

```
✅ 正确的方式
"请为 QuiteNote 生成代码"
"如何实现这个功能"
"为什么会出现这个错误"

❌ 不推荐的方式
"做点什么"
"帮帮我"
"看看这个"
```

#### 10.2.2 组合使用 Skill

```
场景：添加新功能
1. 使用 architecture-design 设计架构
2. 使用 generate-code 生成代码
3. 使用 write-unit-tests 生成测试
4. 使用 code-review 审查代码
```

### 10.3 代码生成最佳实践

#### 10.3.1 验证生成的代码

```
1. 检查是否符合项目规范
2. 运行编译检查
3. 运行测试
4. 进行代码审查
```

#### 10.3.2 集成到现有代码

```
1. 检查依赖关系
2. 更新 Service Container
3. 添加必要的导入
4. 确保向后兼容
```

### 10.4 持续改进

#### 10.4.1 收集反馈

```
- 记录提示词和 Skill 的使用效果
- 收集开发者的反馈
- 识别常见问题和改进点
```

#### 10.4.2 更新提示词和 Skill

```
- 定期更新提示词以反映项目变化
- 优化 Skill 的触发条件
- 添加新的提示词和 Skill
```

### 10.5 团队协作

#### 10.5.1 共享最佳实践

```
- 创建团队内部的使用指南
- 分享成功的案例
- 培训新团队成员
```

#### 10.5.2 建立反馈机制

```
- 定期回顾提示词和 Skill 的效果
- 收集团队的改进建议
- 持续优化开发流程
```

---

## 总结

本文档提供了完整的 Claude Code 提示词和 Skill 规范，用于高效开发和维护 QuiteNote macOS 应用。

### 核心价值

1. **标准化开发**：提供一致的开发指导和规范
2. **提高效率**：通过预定义的提示词快速生成代码
3. **保证质量**：通过代码审查确保代码质量
4. **知识传承**：将最佳实践和经验固化到提示词中
5. **降低门槛**：帮助开发者快速上手项目

### 使用建议

1. **从简单开始**：先使用基本的提示词，逐渐熟悉更复杂的
2. **持续改进**：根据项目发展不断优化提示词和 Skill
3. **团队协作**：分享使用经验和最佳实践
4. **反馈循环**：收集使用反馈，持续改进

### 后续工作

1. 实施提示词和 Skill
2. 收集使用反馈
3. 优化和改进
4. 扩展到其他项目

通过正确使用这些提示词和 Skill，团队可以显著提高开发效率，保证代码质量，促进最佳实践的遵循。

---

**文档结束**