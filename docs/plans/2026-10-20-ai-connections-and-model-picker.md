# 目标

为 Quite Note 的 AI 设置页提供两种清楚的连接方式，并让模型配置从“手填三个技术字段”变成“连接后选择模型”。本计划只定义和验证实施工作，当前不改功能代码。

| 连接方式 | 用户完成配置的路径 | 支持范围 |
| --- | --- | --- |
| Magpie（内置） | 选择 Magpie → 自动探测本机网关 → 自动读取模型目录 → 搜索并选择模型 → 试生成 | 对话请求使用 OpenAI 兼容的 `/v1/chat/completions`；默认网关 `http://127.0.0.1:3425` |
| 自定义 API | 填 Base URL、API Key、模型名 → 试生成 | **仅沿用现有 OpenAI 兼容 Chat Completions 协议**；总结仍要求 JSON 对象输出。不增加 Anthropic Messages、Gemini 或 Responses 适配 |

用户所说“OpenAPI 格式”在这里按“OpenAI 兼容 API”理解。Magpie 自动读取**可选模型列表**，但不任意替用户决定模型。首次使用选一次，之后记住；所选模型不再出现时提示重新选择，不静默切换。全新安装可默认选中 Magpie 连接方式，AI 自动提炼开关仍默认关闭；已有用户继续使用原来的自定义 API 配置。

实施顺序：

1. **配置与迁移：** 增加 `magpie` / `customOpenAI` 连接类型及 Magpie 独立模型 ID。原 `openAIBaseURL`、`openAIModel`、Keychain `openai_api_key` 继续归自定义 API 使用。根据旧 URL、模型或 Key 判断旧用户，迁移时不删除数据。
2. **网关发现：** 请求 `GET /api/hello` 确认目标是 Magpie，再请求 `GET /v1/models`。解码 `data[].id` 及可选显示名；支持搜索、刷新、加载、空列表和错误状态。默认使用 3425 端口；其他本机端口在高级设置中可改。不能读取或改写 Magpie 配置文件。
3. **统一请求配置：** 总结、搜索总结、OCR 整理、试生成都在发起时取得当前 URL、模型和认证快照，共用现有 Chat Completions 请求与解析。Magpie 本机请求用 `magpie-quite-note` 标识调用方；自定义 API 用现有 Keychain 密钥。更新 Key 后立即使内存缓存失效。
4. **重排设置页：** “AI 自动提炼 → 连接方式 → 模型 → 试生成 → 提炼行为 → 高级设置”。Magpie 显示模型选择器，自定义 API 显示三个输入框。关闭 AI 时仍可配置。URL 与 Key 在结束编辑时写入；其余设置沿用即时生效，不增设保存按钮。页脚显示真实连接方式和模型，加入“网关在本机，模型可能在云端处理笔记”的说明。
5. **打包与实机验证：** 对本机 HTTP 添加恰当的 ATS 本地网络配置，不全局放开 HTTP。检查开发包和可用的沙盒包，最后在实际 Quite Note 应用内验证模型目录、试生成及错误提示。

# 输入

- 当前实现：`Sources/QuiteNote/UI/SettingsTabs/AISettingsTab.swift` 的服务商按钮固定为 OpenAI，字段直接绑定现有配置；`Sources/QuiteNote/UI/SettingsOverlayView.swift` 的页脚也固定显示 OpenAI。
- 调用链：`Sources/QuiteNote/AI/AIService.swift` 使用 `/chat/completions`，总结要求 `response_format: {"type":"json_object"}`，连接测试目前只请求 `/models`，Key 在实例内缓存；`Sources/QuiteNote/Records/RecordStore.swift` 和 `Sources/QuiteNote/Records/AI/RecordAICOORDINATOR.swift` 设置并使用模型；OCR 入口会新建 `AIService()`。
- 持久化：`Sources/QuiteNote/Preferences/PreferencesManager.swift` 保存原 Base URL 与模型；`Sources/QuiteNote/Security/KeychainHelper.swift` 保存原 API Key。两种连接方式需要分别记住模型，且切换不能覆盖旧值。
- 构建入口：`Package.swift`、`build-app.sh`、`Info.plist.template`、`QuiteNote-AppStore.entitlements`。`build-app.sh` 会生成最终 Info.plist；计划中的 ATS 改动需覆盖这个入口。
- Magpie 接口依据：[官方集成文档](https://github.com/yetone/magpie/blob/main/docs/integrating.md)：本机默认端口 3425，`/api/hello` 可识别网关，`/v1/models` 返回启用的模型，`/v1/chat/completions` 接受 OpenAI 兼容请求。
- 系统约束：[Apple `NSAllowsLocalNetworking` 文档](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。终端 `curl` 成功不能代替应用内的 ATS 和沙盒验证。

预计修改或新增的文件：

| 工作 | 文件 |
| --- | --- |
| 连接类型、配置快照、旧设置迁移 | 新增 `Sources/QuiteNote/AI/AIConnectionConfig.swift`；修改 `PreferencesManager.swift`、`RecordStore.swift` |
| Magpie 探测与模型目录 | 新增 `Sources/QuiteNote/AI/MagpieCatalogService.swift` |
| 请求路由与试生成 | 修改 `AIService.swift`、`RecordAICOORDINATOR.swift`、OCR 调用处；避免再建一套模型协议 |
| 页面与状态 | 修改 `AISettingsTab.swift`、`SettingsOverlayView.swift`；仅按需新增小型 SwiftUI 组件 |
| 本机 HTTP | 修改 `build-app.sh` 与 `Info.plist.template`，检查最终开发包和沙盒包 |
| 自动化测试 | 新增 `Tests/QuiteNoteTests/AIConnectionConfigTests.swift`、`MagpieCatalogServiceTests.swift`、AI 请求构造与解析测试 |

# 验收标准

| 编号 | 必须通过的场景 | 证据 |
| --- | --- | --- |
| A1 | 新安装显示 Magpie；旧安装保留自定义 API 的 URL、模型和 Key；两种连接方式来回切换不互相覆盖 | 配置迁移单测与设置页检查 |
| A2 | Magpie 运行时自动列出可用模型；未运行、非 Magpie 服务、空列表、超时都有明确状态；刷新有效 | 使用可注入网络响应的单测，以及本机真实网关复测 |
| A3 | 列表按显示名或 ID 搜索；所选模型持久化；模型下线后不静默替换 | 目录与选择状态测试、UI 检查 |
| A4 | 自定义 API 只要求 OpenAI 兼容 Chat Completions；模型手填，不以 `/models` 是否存在判断可用 | 请求构造单测；模拟仅提供 `/chat/completions` 的端点 |
| A5 | “网关已连接”与“所选模型已验证”分开；试生成真实请求得到可解析 JSON 后才显示可用；HTTP 200 空内容、401、5xx 和无效 JSON 明确报错 | AI 请求测试和应用内试生成记录 |
| A6 | 修改 Key 后下一请求使用新 Key；新建的 OCR `AIService()` 使用当前连接；设置切换时在途请求保持原快照 | 请求配置与缓存测试 |
| A7 | 关闭 AI 时仍可配置；键盘、VoiceOver、长模型名、窄设置窗口、加载与错误状态可用 | 实际应用截图与交互检查 |
| A8 | 本机 Magpie HTTP 在实际 macOS 应用中可调用；开发包及可用的沙盒包 Info.plist 包含正确 ATS 设置，未全局放开网络限制 | `swift build`、`swift test`、`./build-app.sh --dev --no-launch`、最终包检查及应用内调用 |

实施时按上述顺序完成，每项先补针对真实行为的测试，再实现，再运行定向测试；最后运行全量 `swift test`、打包和应用内验证。不能把模型目录可达或单独的终端请求当作 A5/A8 已通过。

# 回报格式

后续执行时，每次回报固定填写：**完成了什么、改动文件、运行的命令与通过/失败数量、真实应用验证的截图或日志路径、未通过项及原因**。以 A1–A8 编号逐项标记“通过 / 失败 / 未验证”；未验证不得写成通过。

**本轮计划阶段的测试结果（2026-10-20）：**

| 测试 | 实际结果 | 可证明的范围 |
| --- | --- | --- |
| `GET http://127.0.0.1:3425/api/hello` | HTTP 200，返回 `name=magpie`、版本 `0.1.1293` | 本机默认端口的网关正在运行 |
| `GET http://127.0.0.1:3425/v1/models` | 返回 35 个有 ID 的模型，含 `glm/glm-5.3-flash` | 模型目录可读取；不代表某模型生成可用 |
| `POST /v1/chat/completions`，`glm/glm-5.3-flash`，固定无私人内容样例及 `json_object` | HTTP 200，约 7.45 秒；返回标题、总结、置信度、标签、关键词，字段类型检查通过 | 该模型的本机网关请求与当前总结格式可工作 |
| 当前仓库 `swift test --quiet` | 退出码 0；QuiteNoteTests 262 项、SharedStorage 6 项、CoreService 17 项，合计 285 项，4 项跳过、0 失败 | 当前代码基线；不代表计划中的新功能已实现 |
| Quite Note 应用内 Magpie 模型检索、试生成和 UI | 未运行，因为功能尚未实现 | A1–A8 的新增功能仍待实施与验收 |

本轮只新增本计划文件，没有改功能代码，也没有修改 Magpie 配置。
