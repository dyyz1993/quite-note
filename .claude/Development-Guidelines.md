# QuiteNote 开发规范文档

> 版本：2.0
> 日期：2025-12-09
> 作者：Claude Code

## 目录

1. [代码规范](#1-代码规范)
2. [架构规范](#2-架构规范)
3. [UI/UX 规范](#3-uiux-规范)
4. [安全规范](#4-安全规范)
5. [性能规范](#5-性能规范)
6. [测试规范](#6-测试规范)
7. [文档规范](#7-文档规范)
8. [Git 规范](#8-git-规范)
9. [CI/CD 规范](#9-cicd-规范)
10. [部署规范](#10-部署规范)

---

## 1. 代码规范

### 1.1 Swift 编码规范

#### 1.1.1 命名约定

**类和结构体**
```swift
// ✅ 正确：使用 PascalCase
class RecordManager
struct UserPreferences
enum ConnectionState

// ❌ 错误：使用下划线或驼峰
class record_manager
struct user_preferences
enum connectionState
```

**变量和函数**
```swift
// ✅ 正确：使用 camelCase
let recordCount = 0
func processRecord(_ record: Record)
private var internalState = false

// ❌ 错误：使用下划线或 PascalCase
let record_count = 0
func ProcessRecord(_ record: Record)
private var InternalState = false
```

**常量**
```swift
// ✅ 正确：使用 PascalCase
private let MaxRecordCount = 1000
static let DefaultTimeout: TimeInterval = 30.0

// ❌ 错误：使用全大写或下划线
private let MAX_RECORD_COUNT = 1000
static let default_timeout: TimeInterval = 30.0
```

**协议**
```swift
// ✅ 正确：使用形容词或名词，PascalCase
protocol Configurable
protocol DataProcessor
protocol NetworkService

// ❌ 错误：使用后缀或动词形式
protocol ConfigurableProtocol
protocol DataProcessing
protocol NetworkServiceProvider
```

#### 1.1.2 代码格式

**缩进和空格**
```swift
// ✅ 正确：使用 4 个空格缩进，运算符前后加空格
func calculateTotal(items: [Item]) -> Double {
    var total: Double = 0.0

    for item in items {
        total += item.price * Double(item.quantity)
    }

    return total
}

// ❌ 错误：使用 Tab 或不一致的空格
func calculateTotal(items:[Item])->Double{
    var total:Double=0.0
    for item in items{
        total+=item.price*Double(item.quantity)
    }
    return total
}
```

**大括号风格**
```swift
// ✅ 正确：K&R 风格，左大括号不换行
class RecordManager {
    func processRecord(_ record: Record) {
        if record.isValid {
            // 处理逻辑
        } else {
            // 错误处理
        }
    }
}

// ❌ 错误：Allman 风格或其他
class RecordManager
{
    func processRecord(_ record: Record)
    {
        if record.isValid
        {
            // 处理逻辑
        }
        else
        {
            // 错误处理
        }
    }
}
```

**行长度**
```swift
// ✅ 正确：行长度不超过 120 字符，长行适当换行
let result = veryLongFunctionName(
    parameter1: value1,
    parameter2: value2,
    parameter3: value3
)

// ❌ 错误：单行过长
let result = veryLongFunctionName(parameter1: value1, parameter2: value2, parameter3: value3, parameter4: value4)
```

#### 1.1.3 注释规范

**文件头注释**
```swift
/*
 * Copyright (c) 2025 QuiteNote. All rights reserved.
 * Created on 2025-12-09.
 *
 * This file contains the RecordManager class which handles
 * record processing operations including validation, storage,
 * and retrieval.
 */

import Foundation
```

**类和方法注释**
```swift
/// Manages record operations including CRUD operations and validation.
/// This class is responsible for handling all record-related business logic.
class RecordManager {
    /// Processes a record by validating and storing it.
    /// - Parameter record: The record to process
    /// - Returns: True if processing succeeded, false otherwise
    /// - Throws: RecordError if validation fails
    func processRecord(_ record: Record) async throws -> Bool {
        // 实现
    }
}
```

**代码内注释**
```swift
// ✅ 正确：解释为什么这样做，而不是做了什么
// 使用延迟初始化以避免启动时的性能开销
private lazy var heavyComputation = performHeavyOperation()

// 使用队列确保线程安全
queue.async { [weak self] in
    self?.updateInternalState()
}

// ❌ 错误：只说明做了什么
// 初始化变量
let count = 0

// 调用函数
processData()
```

#### 1.1.4 Swift 特定规范

**可选类型处理**
```swift
// ✅ 正确：安全地处理可选类型
if let value = optionalValue {
    // 使用 value
} else {
    // 处理 nil 情况
}

// 或使用 guard
guard let value = optionalValue else {
    return nil
}
// 使用 value

// ❌ 错误：强制解包
let value = optionalValue!  // 可能崩溃
```

**内存管理**
```swift
// ✅ 正确：使用 weak 避免循环引用
class ViewModel: ObservableObject {
    weak var delegate: ViewModelDelegate?

    deinit {
        print("ViewModel deallocated")
    }
}

// 使用 [weak self] 捕获列表
button.action = { [weak self] in
    self?.handleAction()
}

// ❌ 错误：使用 strong 引用导致内存泄漏
button.action = { [self] in
    self.handleAction()  // 可能导致循环引用
}
```

**错误处理**
```swift
// ✅ 正确：使用 Swift 的错误处理机制
enum RecordError: Error {
    case invalidData
    case networkError
    case permissionDenied
}

func processRecord(_ record: Record) throws -> ProcessedRecord {
    guard record.isValid else {
        throw RecordError.invalidData
    }

    do {
        let result = try networkService.process(record)
        return result
    } catch {
        throw RecordError.networkError
    }
}

// ❌ 错误：返回错误码或忽略错误
func processRecord(_ record: Record) -> (Bool, String?) {
    if !record.isValid {
        return (false, "Invalid data")
    }
    return (true, nil)
}
```

### 1.2 SwiftUI 规范

#### 1.2.1 视图结构

```swift
// ✅ 正确：清晰的视图层次结构
struct RecordListView: View {
    @StateObject private var viewModel: RecordListViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Records")
                .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            viewModel.loadRecords()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            LoadingView()
        } else if viewModel.records.isEmpty {
            EmptyStateView()
        } else {
            recordList
        }
    }

    private var recordList: some View {
        List {
            ForEach(viewModel.records) { record in
                RecordRowView(record: record)
            }
            .onDelete(perform: deleteRecords)
        }
    }
}
```

#### 1.2.2 状态管理

```swift
// ✅ 正确：正确使用状态修饰符
class RecordListViewModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published private(set) var selectedRecord: Record?
}

struct RecordDetailView: View {
    @ObservedObject var viewModel: RecordDetailViewModel
    @State private var isEditing = false
    @Binding var selectedRecord: Record?

    var body: some View {
        // 视图实现
    }
}
```

#### 1.2.3 性能优化

```swift
// ✅ 正确：优化视图性能
struct OptimizedListView: View {
    let records: [Record]

    var body: some View {
        // 使用 LazyVStack 提升性能
        LazyVStack {
            ForEach(records) { record in
                RecordRowView(record: record)
                    .id(record.id)  // 确保唯一标识
            }
        }
        // 使用 @ViewBuilder 减少视图构建
        .background(Color.themeBackground)
    }
}

// 使用 @StateObject 避免重复初始化
@StateObject private var viewModel = RecordListViewModel()

// 使用 .equatable 避免不必要的重绘
struct RecordRowView: View, Equatable {
    let record: Record

    var body: some View {
        // 视图实现
    }

    static func == (lhs: RecordRowView, rhs: RecordRowView) -> Bool {
        lhs.record == rhs.record
    }
}
```

### 1.3 代码组织

#### 1.3.1 文件结构

```swift
// ✅ 正确：按功能组织代码
import Foundation

// MARK: - Models
struct Record: Identifiable, Codable {
    let id: UUID
    let content: String
    let timestamp: Date
}

// MARK: - Protocols
protocol RecordService {
    func getRecords() async throws -> [Record]
    func addRecord(_ record: Record) async throws
}

// MARK: - Implementation
class CoreDataRecordService: RecordService {
    // 实现
}

// MARK: - Extensions
extension Record {
    var formattedDate: String {
        DateFormatter.localizedString(
            from: timestamp,
            dateStyle: .medium,
            timeStyle: .short
        )
    }
}
```

#### 1.3.2 代码分组

使用 MARK 注释组织代码：

```swift
// MARK: - Public Interface
// MARK: - Private Methods
// MARK: - Computed Properties
// MARK: - Initializers
// MARK: - Protocol Conformance
// MARK: - UI Actions
// MARK: - Helpers
```

---

## 2. 架构规范

### 2.1 分层架构

#### 2.1.1 表现层 (Presentation Layer)

```swift
// ✅ 正确：表现层只负责 UI 逻辑
@MainActor
class RecordListViewModel: ObservableObject {
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
        errorMessage = nil

        do {
            records = try await recordService.getRecords()
        } catch {
            errorMessage = error.localizedDescription
        } finally {
            isLoading = false
        }
    }
}
```

**规范要求**：
- 只包含 UI 相关逻辑
- 不直接访问数据层
- 通过依赖注入获取服务
- 使用 @MainActor 确保线程安全

#### 2.1.2 业务层 (Business Layer)

```swift
// ✅ 正确：业务层包含业务逻辑
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
        // 业务逻辑
        guard !content.isEmpty else {
            throw RecordError.invalidContent
        }

        let record = Record(content: content, timestamp: Date())
        return try await repository.save(record)
    }
}
```

**规范要求**：
- 包含核心业务逻辑
- 协调多个数据源
- 不依赖具体实现
- 通过协议定义接口

#### 2.1.3 数据层 (Data Layer)

```swift
// ✅ 正确：数据层只负责数据访问
protocol RecordRepository {
    func save(_ record: Record) async throws -> Record
    func delete(_ id: UUID) async throws
    func getAll() async throws -> [Record]
}

class CoreDataRecordRepository: RecordRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func save(_ record: Record) async throws -> Record {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    // Core Data 保存逻辑
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

**规范要求**：
- 只负责数据的存取
- 不包含业务逻辑
- 实现 Repository 协议
- 处理数据转换

### 2.2 依赖注入

#### 2.2.1 服务注册

```swift
// ✅ 正确：使用依赖注入容器
class ServiceContainer {
    static let shared = ServiceContainer()

    private var services: [String: Any] = [:]

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

// 配置服务
extension ServiceContainer {
    static func configure() {
        // 数据层
        shared.register(RecordRepository.self) {
            CoreDataRecordRepository(context: CoreDataStack.shared.context)
        }

        // 业务层
        shared.register(RecordService.self) {
            RecordService(
                repository: shared.resolve() as RecordRepository,
                aiService: shared.resolve() as AIService,
                searchService: shared.resolve() as SearchService
            )
        }

        // 表现层
        shared.register(RecordListViewModel.self) {
            RecordListViewModel(
                recordService: shared.resolve() as RecordService,
                aiService: shared.resolve() as AIService
            )
        }
    }
}
```

#### 2.2.2 使用依赖注入

```swift
// ✅ 正确：通过构造函数注入
struct RecordListView: View {
    @StateObject private var viewModel: RecordListViewModel

    init(viewModel: RecordListViewModel? = nil) {
        let vm = viewModel ?? ServiceContainer.shared.resolve() as RecordListViewModel
        _viewModel = StateObject(wrappedValue: vm)
    }
}

// ❌ 错误：在视图内部创建依赖
struct RecordListView: View {
    @StateObject private var viewModel = RecordListViewModel(
        recordService: RecordService(),  // 硬编码依赖
        aiService: AIService()
    )
}
```

### 2.3 协议设计

#### 2.3.1 协议定义

```swift
// ✅ 正确：清晰的协议定义
protocol NetworkService {
    /// 网络请求超时时间（秒）
    var timeout: TimeInterval { get set }

    /// 执行 GET 请求
    /// - Parameters:
    ///   - url: 请求 URL
    ///   - headers: 请求头
    /// - Returns: 响应数据
    /// - Throws: NetworkError
    func get(
        from url: URL,
        headers: [String: String]?
    ) async throws -> Data

    /// 执行 POST 请求
    /// - Parameters:
    ///   - url: 请求 URL
    ///   - body: 请求体
    ///   - headers: 请求头
    /// - Returns: 响应数据
    /// - Throws: NetworkError
    func post(
        to url: URL,
        body: Data?,
        headers: [String: String]?
    ) async throws -> Data
}

// ✅ 正确：协议扩展提供默认实现
extension NetworkService {
    var timeout: TimeInterval {
        get { return 30.0 }
        set { /* 默认无操作 */ }
    }

    func get(from url: URL) async throws -> Data {
        return try await get(from: url, headers: nil)
    }
}
```

#### 2.3.2 协议遵循

```swift
// ✅ 正确：明确声明协议遵循
class URLSessionNetworkService: NetworkService {
    var timeout: TimeInterval = 30.0

    func get(
        from url: URL,
        headers: [String: String]?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        // 设置请求头
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }

        return data
    }
}
```

---

## 3. UI/UX 规范

### 3.1 设计原则

#### 3.1.1 一致性

```swift
// ✅ 正确：使用统一的主题系统
struct ThemedButton: View {
    let title: String
    let action: () -> Void
    let style: ButtonStyle

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.themeButton)
                .foregroundColor(.themeButtonText)
        }
        .buttonStyle(ThemeButtonStyle(style: style))
        .cornerRadius(ThemeRadius.md)
    }
}

// 使用统一的按钮样式
struct ContentView: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            ThemedButton(
                title: "Primary",
                action: { /* action */ },
                style: .primary
            )

            ThemedButton(
                title: "Secondary",
                action: { /* action */ },
                style: .secondary
            )
        }
        .padding(ThemeSpacing.p4.rawValue)
    }
}
```

#### 3.1.2 可访问性

```swift
// ✅ 正确：实现可访问性支持
struct AccessibleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.themeButton)
                .foregroundColor(.themeButtonText)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("点击执行 \(title) 操作"))
        .keyboardShortcut(.defaultAction)
    }
}

// ✅ 正确：支持动态字体
struct DynamicText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body) // 使用系统字体，支持动态字体
            .lineSpacing(4) // 行间距
            .allowsTightening(true) // 允许文字压缩
            .lineLimit(3) // 限制行数
    }
}
```

#### 3.1.3 响应式设计

```swift
// ✅ 正确：响应式布局
struct ResponsiveLayout: View {
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 600

            if isCompact {
                VStack(spacing: ThemeSpacing.p4.rawValue) {
                    headerView
                    contentView
                }
            } else {
                HStack(spacing: ThemeSpacing.p6.rawValue) {
                    sidebarView
                        .frame(width: 280)
                    contentView
                }
            }
        }
        .padding(ThemeSpacing.p4.rawValue)
    }

    private var headerView: some View {
        Text("Header")
            .font(.themeH1)
    }

    private var sidebarView: some View {
        VStack {
            Text("Sidebar")
            // 侧边栏内容
        }
        .padding(ThemeSpacing.p4.rawValue)
        .background(Color.themeCard)
        .cornerRadius(ThemeRadius.lg)
    }

    private var contentView: some View {
        VStack {
            Text("Content")
            // 主内容
        }
        .padding(ThemeSpacing.p4.rawValue)
        .background(Color.themeBackground)
        .cornerRadius(ThemeRadius.lg)
    }
}
```

### 3.2 动效规范

#### 3.2.1 动画时长

```swift
// ✅ 正确：使用统一的动画时长
extension Animation {
    /// 快速动画：100ms
    static let quick = Animation.easeOut(duration: 0.1)

    /// 标准动画：300ms
    static let standard = Animation.easeOut(duration: 0.3)

    /// 缓慢动画：500ms
    static let slow = Animation.easeOut(duration: 0.5)

    /// 弹性动画：200ms
    static let spring = Animation.spring(response: 0.2, dampingFraction: 0.8)
}

// 使用统一的动画
struct AnimatedButton: View {
    @State private var isPressed = false

    var body: some View {
        Button("Click me") {
            // action
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.quick, value: isPressed)
        .onLongPressGesture {
            isPressed = true
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
}
```

#### 3.2.2 动画类型

```swift
// ✅ 正确：定义动画类型
enum AnimationType {
    case fadeIn
    case slideIn
    case scaleIn
    case popIn

    var animation: Animation {
        switch self {
        case .fadeIn:
            return .standard
        case .slideIn:
            return .standard.delay(0.1)
        case .scaleIn:
            return .spring
        case .popIn:
            return .quick.delay(0.2)
        }
    }
}

// 使用动画类型
struct AnimatedView: View {
    @State private var isVisible = false

    var body: some View {
        if isVisible {
            Content()
                .transition(.opacity)
                .animation(AnimationType.fadeIn.animation, value: isVisible)
        }
    }
}
```

### 3.3 组件规范

#### 3.3.1 组件设计

```swift
// ✅ 正确：设计可复用的组件
struct CardView<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let shadow: Bool

    init(
        cornerRadius: CGFloat = ThemeRadius.lg.rawValue,
        shadow: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    var body: some View {
        content
            .padding(ThemeSpacing.p4.rawValue)
            .background(Color.themeCard)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(shadow ? 0.1 : 0.0),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

// 使用组件
struct ExampleView: View {
    var body: some View {
        CardView {
            VStack {
                Text("Title")
                    .font(.themeH2)
                Text("Content")
                    .font(.themeBody)
            }
        }
        .padding(ThemeSpacing.p4.rawValue)
    }
}
```

#### 3.3.2 组件状态

```swift
// ✅ 正确：处理组件状态
struct StatefulButton: View {
    enum State {
        case idle
        case loading
        case success
        case error
    }

    let title: String
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if case .loading = state {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(buttonText)
            }
        }
        .buttonStyle(ThemeButtonStyle(style: buttonStyle))
        .disabled(isDisabled)
    }

    private var buttonText: String {
        switch state {
        case .idle:
            return title
        case .loading:
            return "Loading..."
        case .success:
            return "✓ Success"
        case .error:
            return "⚠ Error"
        }
    }

    private var buttonStyle: ThemeButtonStyle.Style {
        switch state {
        case .error:
            return .danger
        default:
            return .primary
        }
    }

    private var isDisabled: Bool {
        switch state {
        case .loading:
            return true
        default:
            return false
        }
    }
}
```

---

## 4. 安全规范

### 4.1 数据安全

#### 4.1.1 敏感数据处理

```swift
// ✅ 正确：安全处理敏感数据
class KeychainManager {
    private let service = "com.quitenote.app"
    private let accessGroup: String?

    init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // 清理旧数据
        SecItemDelete(query as CFDictionary)

        // 保存新数据
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }

    func load(key: String) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw KeychainError.unableToLoad
        }

        return data
    }
}

// 使用 Keychain 保存敏感数据
class SecureDataManager {
    private let keychain = KeychainManager()

    func saveAPIKey(_ key: String) throws {
        guard !key.isEmpty else {
            throw DataManagerError.invalidKey
        }

        let data = key.data(using: .utf8)!
        try keychain.save(key: "apiKey", data: data)
    }

    func loadAPIKey() throws -> String? {
        do {
            let data = try keychain.load(key: "apiKey")
            return String(data: data, encoding: .utf8)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }
}
```

#### 4.1.2 数据加密

```swift
// ✅ 正确：实现数据加密
class EncryptionManager {
    private let keySize = 256
    private let ivSize = 128

    func encrypt(data: Data, key: Data) -> Data? {
        // 使用 AES-GCM 加密
        // 实际实现需要使用 CryptoKit 或第三方库
        return nil
    }

    func decrypt(data: Data, key: Data) -> Data? {
        // 使用 AES-GCM 解密
        // 实际实现需要使用 CryptoKit 或第三方库
        return nil
    }

    func generateKey() -> Data {
        var key = Data(count: keySize / 8)
        _ = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, keySize / 8, bytes)
        }
        return key
    }
}
```

### 4.2 网络安全

#### 4.2.1 HTTPS 配置

```swift
// ✅ 正确：配置网络安全
class NetworkManager {
    private let session: URLSession

    init() {
        var configuration = URLSessionConfiguration.default

        // 配置超时
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0

        // 配置缓存
        configuration.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50MB
            diskCapacity: 100 * 1024 * 1024,   // 100MB
            diskPath: "network_cache"
        )

        // 配置 HTTP 头
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]

        session = URLSession(configuration: configuration)
    }

    func makeRequest(_ request: URLRequest) async throws -> Data {
        // 验证 URL 安全性
        guard let url = request.url,
              url.scheme == "https" else {
            throw NetworkError.insecureRequest
        }

        let (data, response) = try await session.data(for: request)

        // 验证响应
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw NetworkError.invalidResponse
        }

        return data
    }
}
```

#### 4.2.2 API 安全

```swift
// ✅ 正确：实现 API 安全
class APIClient {
    private let baseURL = URL(string: "https://api.quitenote.com")!
    private let networkManager = NetworkManager()
    private let secureDataManager = SecureDataManager()

    func authenticatedRequest(
        endpoint: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil
    ) async throws -> Data {
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // 添加认证头
        if let apiKey = try secureDataManager.loadAPIKey() {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // 添加时间戳
        request.setValue("\(Date().timeIntervalSince1970)", forHTTPHeaderField: "X-Timestamp")

        // 添加请求体
        if let parameters = parameters {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        }

        return try await networkManager.makeRequest(request)
    }
}
```

### 4.3 权限管理

#### 4.3.1 系统权限

```swift
// ✅ 正确：处理系统权限
class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    enum PermissionType {
        case bluetooth
        case microphone
        case camera
        case location
        case notifications

        var description: String {
            switch self {
            case .bluetooth:
                return "NSBluetoothAlwaysUsageDescription"
            case .microphone:
                return "NSMicrophoneUsageDescription"
            case .camera:
                return "NSCameraUsageDescription"
            case .location:
                return "NSLocationAlwaysAndWhenInUseUsageDescription"
            case .notifications:
                return "NSUserNotificationAlertStyle"
            }
        }
    }

    func requestPermission(_ type: PermissionType, completion: @escaping (Bool) -> Void) {
        switch type {
        case .bluetooth:
            requestBluetoothPermission(completion)
        case .microphone:
            requestMicrophonePermission(completion)
        case .camera:
            requestCameraPermission(completion)
        case .location:
            requestLocationPermission(completion)
        case .notifications:
            requestNotificationsPermission(completion)
        }
    }

    private func requestBluetoothPermission(_ completion: @escaping (Bool) -> Void) {
        // CoreBluetooth 权限请求
        // 实际实现需要导入 CoreBluetooth
        completion(true)
    }

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            completion(granted)
        }
    }

    private func requestCameraPermission(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            completion(granted)
        }
    }

    private func requestLocationPermission(_ completion: @escaping (Bool) -> Void) {
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        completion(true)
    }

    private func requestNotificationsPermission(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion(granted)
        }
    }
}
```

---

## 5. 性能规范

### 5.1 内存管理

#### 5.1.1 避免内存泄漏

```swift
// ✅ 正确：使用 weak 和 unowned 避免循环引用
class ViewModel: ObservableObject {
    @Published var data: [String] = []
    private var timer: Timer?

    init() {
        // 使用 weak 避免循环引用
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateData()
        }
    }

    deinit {
        timer?.invalidate()
        print("ViewModel deallocated")
    }

    private func updateData() {
        data.append("Item \(data.count)")
    }
}

// ✅ 正确：使用 cancelable 取消异步操作
class DataFetcher {
    private var cancellables: Set<AnyCancellable> = []

    func fetchData() {
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveValue: { [weak self] data in
                    self?.handleData(data)
                },
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        self?.handleError(error)
                    }
                }
            )
            .store(in: &cancellables)
    }
}
```

#### 5.1.2 优化数据结构

```swift
// ✅ 正确：选择合适的数据结构
class DataProcessor {
    // 使用 Set 提高查找性能
    private var processedIDs: Set<UUID> = []

    // 使用 Dictionary 提高查找性能
    private var recordCache: [UUID: Record] = [:]

    // 使用 Struct 减少内存开销
    struct ProcessedRecord {
        let id: UUID
        let processedData: String
        let timestamp: Date
    }

    func processRecords(_ records: [Record]) -> [ProcessedRecord] {
        return records.compactMap { record in
            guard !processedIDs.contains(record.id) else {
                return nil
            }

            let processedData = process(record.data)
            processedIDs.insert(record.id)
            recordCache[record.id] = record

            return ProcessedRecord(
                id: record.id,
                processedData: processedData,
                timestamp: Date()
            )
        }
    }
}
```

### 5.2 渲染性能

#### 5.2.1 优化视图更新

```swift
// ✅ 正确：减少不必要的视图更新
struct OptimizedListView: View {
    let items: [Item]

    var body: some View {
        // 使用 LazyVStack 提升性能
        LazyVStack {
            ForEach(items) { item in
                ItemRowView(item: item)
                    .id(item.id)  // 确保唯一标识
            }
        }
        .background(Color.themeBackground)
    }
}

// 使用 Equatable 减少重绘
struct ItemRowView: View, Equatable {
    let item: Item

    var body: some View {
        HStack {
            Text(item.title)
            Spacer()
            Text(item.subtitle)
        }
        .padding()
    }

    static func == (lhs: ItemRowView, rhs: ItemRowView) -> Bool {
        lhs.item == rhs.item
    }
}

// 使用 @ViewBuilder 减少视图构建开销
@ViewBuilder
func buildContent(for state: ViewState) -> some View {
    switch state {
    case .loading:
        LoadingView()
    case .empty:
        EmptyStateView()
    case .error(let message):
        ErrorView(message: message)
    case .success(let data):
        DataListView(data: data)
    }
}
```

#### 5.2.2 图片和资源优化

```swift
// ✅ 正确：优化图片加载
struct OptimizedImageView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    ProgressView()
                )
                .task {
                    await loadImage()
                }
        }
    }

    @MainActor
    private func loadImage() async {
        do {
            let data = try await URLSession.shared.data(from: url)
            image = NSImage(data: data)
        } catch {
            print("Failed to load image: \(error)")
        }
    }
}

// ✅ 正确：使用图片缓存
class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, NSData>()

    func image(at url: URL) -> NSImage? {
        guard let data = cache.object(forKey: url as NSURL) else {
            return nil
        }
        return NSImage(data: data as Data)
    }

    func cache(image: NSImage, at url: URL) {
        guard let data = image.tiffRepresentation else {
            return
        }
        cache.setObject(data as NSData, forKey: url as NSURL)
    }
}
```

### 5.3 网络性能

#### 5.3.1 请求优化

```swift
// ✅ 正确：实现请求缓存
class CachingNetworkService {
    private let urlCache = URLCache(
        memoryCapacity: 50 * 1024 * 1024,  // 50MB
        diskCapacity: 100 * 1024 * 1024,   // 100MB
        diskPath: "network_cache"
    )

    func fetchData(from url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)

        let (data, response) = try await URLSession.shared.data(for: request)

        // 验证缓存
        if let cachedResponse = URLCache.shared.cachedResponse(for: request) {
            return cachedResponse.data
        }

        return data
    }

    func clearCache() {
        urlCache.removeAllCachedResponses()
    }
}

// ✅ 正确：实现请求去重
class DeduplicatingNetworkService {
    private var pendingRequests: [String: Task<Data, Error>] = [:]

    func fetchData(from url: URL) async throws -> Data {
        let key = url.absoluteString

        // 检查是否有待处理的请求
        if let task = pendingRequests[key] {
            return try await task.value
        }

        // 创建新任务
        let task = Task {
            defer { pendingRequests.removeValue(forKey: key) }
            return try await performRequest(from: url)
        }

        pendingRequests[key] = task
        return try await task.value
    }

    private func performRequest(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
```

#### 5.3.2 并发控制

```swift
// ✅ 正确：控制并发数量
class ConcurrentNetworkService {
    private let maxConcurrentRequests = 3
    private let semaphore = DispatchSemaphore(value: 3)

    func fetchData(from urls: [URL]) async throws -> [Data] {
        return try await withThrowingTaskGroup(of: Data.self) { group in
            for url in urls {
                group.addTask {
                    return try await self.fetchSingleURL(url)
                }
            }

            var results: [Data] = []
            for try await result in group {
                results.append(result)
            }

            return results
        }
    }

    private func fetchSingleURL(_ url: URL) async throws -> Data {
        _ = semaphore.wait(timeout: .now() + .seconds(30))

        defer { semaphore.signal() }

        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
```

---

## 6. 测试规范

### 6.1 单元测试

#### 6.1.1 测试结构

```swift
import XCTest
@testable import QuiteNote

final class RecordServiceTests: XCTestCase {
    private var recordService: RecordService!
    private var mockRepository: MockRecordRepository!
    private var mockAIService: MockAIService!

    override func setUp() {
        super.setUp()
        mockRepository = MockRecordRepository()
        mockAIService = MockAIService()
        recordService = RecordService(
            repository: mockRepository,
            aiService: mockAIService
        )
    }

    override func tearDown() {
        recordService = nil
        mockRepository = nil
        mockAIService = nil
        super.tearDown()
    }

    func testAddRecord_WithValidData_ShouldSaveSuccessfully() async throws {
        // Given
        let record = Record(content: "Test content", timestamp: Date())

        // When
        let savedRecord = try await recordService.addRecord(record)

        // Then
        XCTAssertTrue(mockRepository.saveCalled)
        XCTAssertEqual(mockRepository.savedRecord?.content, record.content)
        XCTAssertEqual(savedRecord.content, record.content)
    }

    func testAddRecord_WithEmptyContent_ShouldThrowError() async throws {
        // Given
        let record = Record(content: "", timestamp: Date())

        // When & Then
        await XCTAssertThrowsError(
            try await recordService.addRecord(record)
        ) { error in
            XCTAssertEqual(error as? RecordError, .invalidContent)
        }
    }

    func testGetRecords_WhenRepositoryReturnsData_ShouldReturnRecords() async throws {
        // Given
        let expectedRecords = [Record(content: "Test", timestamp: Date())]
        mockRepository.stubbedRecords = expectedRecords

        // When
        let records = try await recordService.getRecords()

        // Then
        XCTAssertTrue(mockRepository.getAllCalled)
        XCTAssertEqual(records, expectedRecords)
    }
}

// Mock 实现
class MockRecordRepository: RecordRepository {
    var saveCalled = false
    var savedRecord: Record?
    var getAllCalled = false
    var stubbedRecords: [Record] = []

    func save(_ record: Record) async throws -> Record {
        saveCalled = true
        savedRecord = record
        return record
    }

    func getAll() async throws -> [Record] {
        getAllCalled = true
        return stubbedRecords
    }
}
```

#### 6.1.2 测试覆盖率

```swift
// ✅ 正确：测试各种场景
class NetworkServiceTests: XCTestCase {
    func testGetRequest_WithValidURL_ShouldReturnData() async throws {
        // 测试成功场景
    }

    func testGetRequest_WithInvalidURL_ShouldThrowError() async throws {
        // 测试错误场景
    }

    func testGetRequest_WithTimeout_ShouldThrowTimeoutError() async throws {
        // 测试超时场景
    }

    func testGetRequest_WithRetry_ShouldRetryOnFailure() async throws {
        // 测试重试逻辑
    }

    func testPostRequest_WithData_ShouldIncludeBody() async throws {
        // 测试请求体
    }
}
```

### 6.2 UI 测试

#### 6.2.1 SwiftUI 视图测试

```swift
import XCTest
import SwiftUI
import ViewInspector
@testable import QuiteNote

extension RecordListView: Inspectable { }

final class RecordListViewTests: XCTestCase {
    func testRecordListView_WhenLoading_ShouldShowLoadingView() throws {
        // Given
        let mockViewModel = MockRecordListViewModel()
        mockViewModel.isLoading = true

        let view = RecordListView(viewModel: mockViewModel)

        // When
        let loadingView = try view.inspect().find(viewWithId: "loadingView")

        // Then
        XCTAssertTrue(loadingView.exists)
    }

    func testRecordListView_WhenEmpty_ShouldShowEmptyState() throws {
        // Given
        let mockViewModel = MockRecordListViewModel()
        mockViewModel.records = []

        let view = RecordListView(viewModel: mockViewModel)

        // When
        let emptyState = try view.inspect().find(viewWithId: "emptyState")

        // Then
        XCTAssertTrue(emptyState.exists)
    }

    func testRecordListView_WhenHasRecords_ShouldShowList() throws {
        // Given
        let mockViewModel = MockRecordListViewModel()
        mockViewModel.records = [Record(content: "Test", timestamp: Date())]

        let view = RecordListView(viewModel: mockViewModel)

        // When
        let listView = try view.inspect().find(viewWithId: "recordList")

        // Then
        XCTAssertTrue(listView.exists)
        XCTAssertEqual(try listView.list().rowCount(), 1)
    }
}
```

#### 6.2.2 交互测试

```swift
final class ButtonInteractionTests: XCTestCase {
    func testButtonTap_ShouldExecuteAction() throws {
        // Given
        var actionExecuted = false
        let button = Button("Tap me") {
            actionExecuted = true
        }

        // When
        try button.inspect().button().tap()

        // Then
        XCTAssertTrue(actionExecuted)
    }

    func testTextFieldInput_ShouldUpdateValue() throws {
        // Given
        let testString = "Hello World"
        @ViewBuilder
        func makeTextField() -> some View {
            TextField("Enter text", text: .constant(""))
        }

        // When
        let textField = try makeTextField().inspect().textField()
        try textField.setText(testString)

        // Then
        XCTAssertEqual(try textField.string(), testString)
    }
}
```

### 6.3 性能测试

#### 6.3.1 性能基准测试

```swift
final class PerformanceTests: XCTestCase {
    func testRecordProcessing_Performance() throws {
        let recordService = RecordService(
            repository: MockRecordRepository(),
            aiService: MockAIService()
        )

        measure {
            for _ in 0..<1000 {
                let record = Record(content: "Test content", timestamp: Date())
                _ = try! recordService.addRecord(record)
            }
        }
    }

    func testImageLoading_Performance() throws {
        let imageCache = ImageCache.shared
        let testImage = NSImage(size: NSSize(width: 100, height: 100))

        measure {
            for i in 0..<100 {
                let url = URL(string: "https://example.com/image\(i).jpg")!
                imageCache.cache(image: testImage, at: url)
                _ = imageCache.image(at: url)
            }
        }
    }

    func testUIRendering_Performance() throws {
        let records = (0..<100).map { i in
            Record(content: "Record \(i)", timestamp: Date())
        }

        measure {
            let view = RecordListView(viewModel: MockViewModel(records: records))
            _ = try view.inspect()
        }
    }
}
```

---

## 7. 文档规范

### 7.1 代码注释

#### 7.1.1 文档注释格式

```swift
/// A service that manages record operations including CRUD operations.
///
/// This service coordinates between the repository layer and business logic,
/// providing a clean interface for record management operations.
///
/// ```swift
/// let service = RecordService(repository: repository, aiService: aiService)
/// let record = try await service.addRecord(content: "New record")
/// ```
///
/// - Note: This service is thread-safe and can be used from multiple threads.
/// - Warning: Ensure that the repository and AI service are properly configured
///           before using this service.
public class RecordService {
    /// The repository for data persistence operations.
    private let repository: RecordRepository

    /// The AI service for intelligent record processing.
    private let aiService: AIService

    /// Initializes a new instance of RecordService.
    ///
    /// - Parameters:
    ///   - repository: The repository for data operations.
    ///                 Must not be nil.
    ///   - aiService: The AI service for processing.
    ///                Must not be nil.
    ///
    /// - Precondition: Both repository and aiService must be properly configured.
    public init(repository: RecordRepository, aiService: AIService) {
        self.repository = repository
        self.aiService = aiService
    }

    /// Adds a new record to the system.
    ///
    /// This method validates the record content, processes it with AI if enabled,
    /// and saves it to the repository.
    ///
    /// - Parameter content: The content of the record to add.
    ///                      Must not be empty.
    ///
    /// - Returns: The created record with additional metadata.
    ///
    /// - Throws: `RecordError.invalidContent` if the content is empty.
    ///           `RecordError.processingFailed` if AI processing fails.
    ///           `RecordError.saveFailed` if saving to repository fails.
    ///
    /// - SeeAlso: `Record`
    /// - SeeAlso: `RecordError`
    public func addRecord(content: String) async throws -> Record {
        // Implementation
    }
}
```

#### 7.1.2 内联注释

```swift
// ✅ 正确：解释复杂的逻辑
/// Calculates the exponential moving average for the given data points.
/// This algorithm gives more weight to recent data points, making it
/// more responsive to new information while maintaining stability.
///
/// Formula: EMA_today = (value_today * k) + (EMA_yesterday * (1 - k))
/// Where k = 2 / (N + 1), N = period
func calculateEMA(data: [Double], period: Int) -> [Double] {
    guard data.count > period else {
        return [] // Insufficient data for EMA calculation
    }

    let multiplier = 2.0 / Double(period + 1) // Smoothing factor
    var ema: [Double] = []

    // Calculate initial SMA for seed value
    let initialSMA = Array(data.prefix(period)).reduce(0, +) / Double(period)
    ema.append(initialSMA)

    // Calculate EMA for remaining data points
    for i in period..<data.count {
        let previousEMA = ema.last!
        let currentValue = data[i]
        let newEMA = (currentValue * multiplier) + (previousEMA * (1 - multiplier))
        ema.append(newEMA)
    }

    return ema
}

// ❌ 错误：不必要的注释
func calculateSum(numbers: [Int]) -> Int {
    var sum = 0 // Initialize sum to zero

    for number in numbers { // Loop through all numbers
        sum += number // Add number to sum
    }

    return sum // Return the final sum
}
```

### 7.2 API 文档

#### 7.2.1 API 规范文档

```markdown
# Record API

## Overview

The Record API provides endpoints for managing records in the system. It supports CRUD operations and bulk operations for efficient data management.

## Base URL

```
https://api.quitenote.com/v1
```

## Authentication

All requests must include an Authorization header with a valid API key:

```
Authorization: Bearer <api_key>
```

## Endpoints

### GET /records

Retrieves a list of records with optional filtering and pagination.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| page | integer | No | Page number (default: 1) |
| limit | integer | No | Records per page (default: 20, max: 100) |
| search | string | No | Search query for content |
| from | string | No | Start date (ISO 8601 format) |
| to | string | No | End date (ISO 8601 format) |

**Response:**

```json
{
  "data": [
    {
      "id": "uuid",
      "content": "Record content",
      "timestamp": "2025-12-09T10:30:00Z",
      "aiSummary": "AI generated summary",
      "tags": ["tag1", "tag2"]
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 100,
    "pages": 5
  }
}
```

**Example:**

```bash
curl -X GET "https://api.quitenote.com/v1/records?page=1&limit=10&search=test"
-H "Authorization: Bearer your_api_key"
```

### POST /records

Creates a new record.

**Request Body:**

```json
{
  "content": "Record content",
  "tags": ["tag1", "tag2"]
}
```

**Response:**

```json
{
  "id": "uuid",
  "content": "Record content",
  "timestamp": "2025-12-09T10:30:00Z",
  "aiSummary": "AI generated summary",
  "tags": ["tag1", "tag2"]
}
```

### PUT /records/{id}

Updates an existing record.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| id | string | Record UUID |

**Request Body:**

```json
{
  "content": "Updated content",
  "tags": ["new_tag"]
}
```

### DELETE /records/{id}

Deletes a record.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| id | string | Record UUID |

**Response:**

```json
{
  "success": true,
  "message": "Record deleted successfully"
}
```

## Error Responses

All endpoints return standardized error responses:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": "Additional error details"
  }
}
```

**Common Error Codes:**

| Code | Description |
|------|-------------|
| INVALID_REQUEST | Invalid request parameters |
| UNAUTHORIZED | Missing or invalid authentication |
| FORBIDDEN | Insufficient permissions |
| NOT_FOUND | Resource not found |
| RATE_LIMITED | Too many requests |
| SERVER_ERROR | Internal server error |

## Rate Limiting

The API enforces rate limits to ensure fair usage:

- **Read operations**: 100 requests per minute
- **Write operations**: 60 requests per minute
- **Bulk operations**: 10 requests per minute

Rate limit information is included in response headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1641072000
```

## SDK Usage

### Swift

```swift
import QuiteNoteSDK

let client = APIClient(apiKey: "your_api_key")

// Get records
do {
    let records = try await client.getRecords(page: 1, limit: 20)
    print("Retrieved \(records.count) records")
} catch {
    print("Error: \(error)")
}

// Create record
let newRecord = Record(content: "New record content")
do {
    let savedRecord = try await client.createRecord(newRecord)
    print("Created record: \(savedRecord.id)")
} catch {
    print("Error: \(error)")
}
```

### JavaScript

```javascript
const client = new QuiteNoteClient('your_api_key');

// Get records
const records = await client.getRecords({
    page: 1,
    limit: 20,
    search: 'test'
});

// Create record
const record = await client.createRecord({
    content: 'New record content',
    tags: ['tag1', 'tag2']
});
```

## Changelog

### v1.2.0 (2025-12-09)

- Added bulk delete endpoint
- Improved search performance
- Added rate limiting headers

### v1.1.0 (2025-11-15)

- Added AI summary field
- Improved error handling
- Added pagination metadata

### v1.0.0 (2025-10-01)

- Initial release
- Basic CRUD operations
- Authentication support
```

---

## 8. Git 规范

### 8.1 提交信息规范

#### 8.1.1 提交信息格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type（必需）**：
- `feat`：新功能
- `fix`：修复 bug
- `docs`：文档更新
- `style`：代码格式调整
- `refactor`：重构
- `test`：测试相关
- `chore`：构建过程或辅助工具的变动

**Scope（可选）**：
- `ui`：用户界面
- `api`：API 相关
- `db`：数据库
- `config`：配置
- `test`：测试
- `docs`：文档

**Subject（必需）**：
- 使用英文现在时
- 首字母小写
- 不用句号结尾

**Body（可选）**：
- 说明代码变更的动机
- 与前一版本的区别

**Footer（可选）**：
- 关联的 Issue 编号
- 破坏性变更说明

#### 8.1.2 提交示例

```bash
# ✅ 正确的提交信息
git commit -m "feat(ui): add dark mode toggle"
git commit -m "fix(api): handle null values in response"
git commit -m "docs(readme): update installation instructions"
git commit -m "refactor(core): extract validation logic"

# ❌ 错误的提交信息
git commit -m "update"
git commit -m "fix bug"
git commit -m "add new feature"
git commit -m "stuff"
```

#### 8.1.3 完整示例

```bash
feat(api): add record search functionality

- Implement full-text search using Elasticsearch
- Add search filters for date range and tags
- Include pagination support with 20 items per page
- Add search history tracking

Closes #123
```

### 8.2 分支管理

#### 8.2.1 分支命名规范

```bash
# 主分支
main
develop

# 功能分支
feature/user-authentication
feature/dark-mode
feature/export-functionality

# 修复分支
hotfix/login-issue
hotfix/security-patch

# 发布分支
release/v1.2.0
release/v2.0.0
```

#### 8.2.2 Git Flow 工作流

```bash
# 开始新功能
git checkout develop
git pull origin develop
git checkout -b feature/new-feature

# 开发完成后合并
git checkout develop
git merge feature/new-feature
git branch -d feature/new-feature
git push origin develop

# 发布流程
git checkout develop
git pull origin develop
git checkout -b release/v1.2.0
git checkout main
git merge release/v1.2.0
git tag -a v1.2.0 -m "Release version 1.2.0"
git push origin main --tags
git branch -d release/v1.2.0
```

### 8.3 Pull Request 规范

#### 8.3.1 PR 模板

```markdown
## Summary
Brief description of the changes

## Test plan
- [ ] Test case 1
- [ ] Test case 2
- [ ] Test case 3

## Documentation
- [ ] Documentation updated
- [ ] No documentation changes needed

## Breaking changes
- [ ] No breaking changes
- [ ] Breaking changes (list them below)

## Additional notes
Any additional information
```

#### 8.3.2 PR 检查清单

```markdown
# PR Checklist

## Before submitting

- [ ] I have read the [Contributing Guidelines](CONTRIBUTING.md)
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] Any dependent changes have been merged and published

## Code quality

- [ ] All tests pass locally with my changes
- [ ] New and existing unit tests pass locally with my changes
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] The code follows the project's style guidelines
- [ ] I have performed a self-review of my code
```

---

## 9. CI/CD 规范

### 9.1 GitHub Actions 配置

#### 9.1.1 构建工作流

```yaml
# .github/workflows/build.yml
name: Build and Test

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: macos-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: latest-stable

    - name: Cache Carthage dependencies
      uses: actions/cache@v3
      with:
        path: Carthage
        key: ${{ runner.os }}-carthage-${{ hashFiles('**/Cartfile.resolved') }}
        restore-keys: |
          ${{ runner.os }}-carthage-

    - name: Install dependencies
      run: |
        carthage bootstrap --platform iOS --use-xcframeworks

    - name: Run SwiftLint
      run: |
        swiftlint lint --reporter github-actions-logging

    - name: Build project
      run: |
        xcodebuild clean build \
          -workspace QuiteNote.xcworkspace \
          -scheme QuiteNote \
          -destination 'platform=iOS Simulator,name=iPhone 14'

    - name: Run tests
      run: |
        xcodebuild test \
          -workspace QuiteNote.xcworkspace \
          -scheme QuiteNote \
          -destination 'platform=iOS Simulator,name=iPhone 14' \
          -enableCodeCoverage YES

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        fail_ci_if_error: true
```

#### 9.1.2 发布工作流

```yaml
# .github/workflows/release.yml
name: Release

on:
  release:
    types: [published]

jobs:
  build-and-release:
    runs-on: macos-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: latest-stable

    - name: Build release
      run: |
        xcodebuild clean archive \
          -workspace QuiteNote.xcworkspace \
          -scheme QuiteNote \
          -archivePath build/QuiteNote.xcarchive \
          -configuration Release

    - name: Export app
      run: |
        xcodebuild -exportArchive \
          -archivePath build/QuiteNote.xcarchive \
          -exportPath build \
          -exportOptionsPlist ExportOptions.plist

    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: QuiteNote-${{ github.event.release.tag_name }}
        path: build/*.ipa
```

### 9.2 代码质量检查

#### 9.2.1 SwiftLint 配置

```yaml
# .swiftlint.yml
disabled_rules:
  - line_length
  - type_body_length
  - file_length

opt_in_rules:
  - empty_count
  - closure_end_indentation
  - explicit_type_interface
  - private_outlet
  - sorted_imports

included:
  - Sources
  - Tests

excluded:
  - Carthage
  - Pods
  - build

line_length:
  warning: 120
  error: 150

type_body_length:
  warning: 300
  error: 500

file_length:
  warning: 500
  error: 800

cyclomatic_complexity:
  warning: 10
  error: 20

function_body_length:
  warning: 30
  error: 50

identifier_name:
  min_length: 3
  max_length: 40
```

#### 9.2.2 代码覆盖率

```yaml
# .github/workflows/coverage.yml
name: Code Coverage

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  coverage:
    runs-on: macos-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: latest-stable

    - name: Run tests with coverage
      run: |
        xcodebuild test \
          -workspace QuiteNote.xcworkspace \
          -scheme QuiteNote \
          -destination 'platform=iOS Simulator,name=iPhone 14' \
          -enableCodeCoverage YES

    - name: Generate coverage report
      run: |
        xcrun xccov view --report --json build/Coverage.profdata > coverage.json

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        token: ${{ secrets.CODECOV_TOKEN }}
        fail_ci_if_error: true
```

---

## 10. 部署规范

### 10.1 开发环境

#### 10.1.1 本地开发

```bash
# 1. 克隆仓库
git clone https://github.com/quitenote/quitenote.git
cd quiteNote

# 2. 安装依赖
carthage bootstrap --platform iOS --use-xcframeworks

# 3. 打开项目
open QuiteNote.xcworkspace

# 4. 运行项目
# 在 Xcode 中选择模拟器并运行
```

#### 10.1.2 环境变量

```bash
# 创建 .env 文件
API_BASE_URL=https://api-dev.quitenote.com
API_KEY=your_development_api_key
LOG_LEVEL=debug
```

### 10.2 测试环境

#### 10.2.1 自动化部署

```bash
# 测试环境部署脚本
#!/bin/bash

set -e

echo "Deploying to staging environment..."

# 构建
xcodebuild clean archive \
  -workspace QuiteNote.xcworkspace \
  -scheme QuiteNote-Staging \
  -archivePath build/QuiteNote-Staging.xcarchive

# 导出
xcodebuild -exportArchive \
  -archivePath build/QuiteNote-Staging.xcarchive \
  -exportPath build/staging \
  -exportOptionsPlist ExportOptions-Staging.plist

# 上传到 TestFlight
xcrun altool --upload-app \
  -f build/staging/QuiteNote.ipa \
  -u $APPLE_ID \
  -p $APPLE_PASSWORD \
  --type ios

echo "Deployment to staging completed!"
```

### 10.3 生产环境

#### 10.3.1 发布流程

```bash
# 生产环境发布脚本
#!/bin/bash

set -e

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

echo "Releasing version $VERSION..."

# 1. 更新版本号
sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $VERSION/" \
  QuiteNote/Info.plist

# 2. 提交更改
git add QuiteNote/Info.plist
git commit -m "chore: bump version to $VERSION"
git tag -a v$VERSION -m "Release version $VERSION"
git push origin main --tags

# 3. 构建发布版本
xcodebuild clean archive \
  -workspace QuiteNote.xcworkspace \
  -scheme QuiteNote \
  -archivePath build/QuiteNote-Release.xcarchive \
  -configuration Release

# 4. 导出
xcodebuild -exportArchive \
  -archivePath build/QuiteNote-Release.xcarchive \
  -exportPath build/release \
  -exportOptionsPlist ExportOptions-AppStore.plist

# 5. 提交到 App Store
xcrun altool --upload-app \
  -f build/release/QuiteNote.ipa \
  -u $APPLE_ID \
  -p $APPLE_PASSWORD \
  --type ios

echo "Release $VERSION completed!"
```

### 10.4 监控和日志

#### 10.4.1 错误监控

```swift
// 错误监控服务
class ErrorMonitoringService {
    static let shared = ErrorMonitoringService()

    func reportError(_ error: Error, context: [String: Any]? = nil) {
        // 上报到错误监控服务（如 Sentry）
        let report = ErrorReport(
            error: error,
            context: context,
            timestamp: Date(),
            user: currentUser,
            appVersion: appVersion
        )

        // 异步上报
        DispatchQueue.global(qos: .background).async {
            self.uploadReport(report)
        }
    }

    private func uploadReport(_ report: ErrorReport) {
        // 实现错误上报逻辑
    }
}

// 使用
do {
    try await someAsyncOperation()
} catch {
    ErrorMonitoringService.shared.reportError(error, context: [
        "operation": "fetchData",
        "timestamp": Date().timeIntervalSince1970
    ])
}
```

#### 10.4.2 性能监控

```swift
// 性能监控
class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    func measure<T>(_ name: String, block: () throws -> T) rethrows -> T {
        let startTime = CACurrentMediaTime()

        defer {
            let endTime = CACurrentMediaTime()
            let duration = endTime - startTime

            // 上报性能数据
            reportMetric(name: name, value: duration, unit: "seconds")
        }

        return try block()
    }

    private func reportMetric(name: String, value: Double, unit: String) {
        // 上报到性能监控服务
    }
}

// 使用
PerformanceMonitor.shared.measure("record_processing") {
    try await processRecords()
}
```

---

## 总结

本开发规范文档涵盖了 QuiteNote 项目开发的各个方面：

1. **代码规范**：命名约定、格式化、注释、Swift 特定规范
2. **架构规范**：分层架构、依赖注入、协议设计
3. **UI/UX 规范**：设计原则、动效、组件设计
4. **安全规范**：数据安全、网络安全、权限管理
5. **性能规范**：内存管理、渲染优化、网络优化
6. **测试规范**：单元测试、UI 测试、性能测试
7. **文档规范**：代码注释、API 文档
8. **Git 规范**：提交信息、分支管理、PR 流程
9. **CI/CD 规范**：GitHub Actions、代码质量、自动化测试
10. **部署规范**：环境配置、发布流程、监控日志

遵循这些规范可以确保代码质量、团队协作效率和项目可维护性。

---

**文档结束**