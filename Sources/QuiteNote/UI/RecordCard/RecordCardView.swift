import SwiftUI
import UniformTypeIdentifiers

/// 单条记录卡片视图
struct RecordCardView: View, Equatable {
    let record: Record
    @Binding var expandedId: UUID?
    @Binding var searchTerm: String
    let store: RecordStore
    @State private var hovering = false
    @State private var isDragHovered = false // 新增：拖拽感应区悬停状态
    @State private var isDragging = false // 新增：是否正在拖拽中
    @State private var showOriginalContent = false
    @State private var showContent = false // 控制内容延迟显示
    @State private var showFullContent = false // 控制是否显示完整内容
    @State private var thumbnailHoverTask: Task<Void, Never>? = nil // 新增：缩略图悬停延迟任务

    // 删除撤回逻辑
    @State var deleteCountdown = 0
    @State private var deleteTimer: Timer? = nil

    // 缓存计算结果，避免重复计算
    var isExpanded: Bool {
        expandedId == record.id
    }

    // 使用@ViewBuilder优化条件渲染
    @ViewBuilder
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 卡片主体内容
            VStack(alignment: .leading, spacing: 0) {
                cardHeader

                if isExpanded {
                    cardExpandedContent
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8)) // 裁剪内容，确保不超出边界
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.themeItem)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isExpanded ? Color.themeFocused : Color.clear, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: isExpanded ? Color.themeShadowMedium : .clear, radius: 10, x: 0, y: 2)
            .compositingGroup() // 确保所有内容作为一个整体渲染，防止内容穿透
            .opacity(isDragging ? 0.5 : 1.0)
            .scaleEffect(isDragging ? 0.98 : 1.0)
            .onDrag {
                // 只有在折叠状态且蒙层已激活时，整个卡片才可拖拽
                if !isExpanded && isDragHovered {
                    isDragging = true
                    store.isInternalDragging = true
                    
                    guard let fileURL = getFileURL(from: record) else {
                        isDragging = false
                        return NSItemProvider(object: "" as NSString)
                    }
                    return NSItemProvider(item: fileURL as NSURL, typeIdentifier: UTType.fileURL.identifier)
                }
                // 否则返回空 provider，不触发拖拽
                return NSItemProvider()
            }
            
            // 左上角隐藏三角感应区 (仅折叠状态)
            if !isExpanded {
                Triangle()
                    .fill(Color.clear)
                    .frame(width: 16, height: 16)
                    .contentShape(Triangle())
                    .onHover { hovered in
                        if hovered {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isDragHovered = true
                            }
                        }
                    }
                    // 保留三角区的 onDrag 确保最初触发点有效
                    .onDrag {
                        isDragging = true
                        store.isInternalDragging = true
                        
                        guard let fileURL = getFileURL(from: record) else {
                            isDragging = false
                            return NSItemProvider(object: "" as NSString)
                        }
                        return NSItemProvider(item: fileURL as NSURL, typeIdentifier: UTType.fileURL.identifier)
                    }

                // 拖拽蒙层
                if isDragHovered {
                    ZStack {
                        Color.themeBackground.opacity(0.85)
                            .blur(radius: 2)
                        
                        VStack(spacing: 8) {
                            LucideView(name: .mousePointer2, size: 24, color: .themeBlue500)
                            Text("拖拽移动")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.themeTextPrimary)
                        }
                    }
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .allowsHitTesting(false) // 让蒙层不干扰底层的拖拽感应
                }
            }
        }
        // 移除了全局动画，避免 zIndex 变化时的布局冲突
        .onHover { isHovering in
            hovering = isHovering
            if !isHovering {
                // 离开整个卡片时才重置蒙层状态
                withAnimation(.easeOut(duration: 0.2)) {
                    isDragHovered = false
                    isDragging = false // 确保离开时也重置拖拽状态
                }
            }
        }
        .pointingHandCursor()
    }

    // MARK: - 辅助函数

    /// 根据记录类型获取文件URL
    private func getFileURL(from record: Record) -> URL? {
        switch record.type {
        case .file, .folder, .image, .screenshot:
            // 资源记录：解析虚拟路径
            return record.sourceUrl.flatMap { FileCoordinator.shared.resolveVirtualPath($0) }

        case .url:
            // URL记录：直接返回URL字符串
            return URL(string: record.content)

        case .text:
            // 文本记录：创建临时 .md 文件，使用唯一子目录以保持原名
            let tempBaseDir = FileManager.default.temporaryDirectory.appendingPathComponent("QuiteNote_Export")
            let uniqueDir = tempBaseDir.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)

            let filename = (record.title ?? "记录") + ".md"
            let fileURL = uniqueDir.appendingPathComponent(filename)

            // 写入内容到临时文件
            try? record.content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL

        default:
            return nil
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Middle: Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    // 缩略图或图标 (图标大小 16x16)
                    if record.type == .image || record.type == .screenshot {
                        GeometryReader { geo in
                            RecordThumbnailView(record: record, size: 16)
                                .onHover { hovered in
                                    thumbnailHoverTask?.cancel()
                                    if hovered {
                                        thumbnailHoverTask = Task {
                                            try? await Task.sleep(nanoseconds: 300 * 1_000_000) // 延迟 300ms
                                            if !Task.isCancelled {
                                                // 获取图标在全局坐标系中的位置
                                                let frame = geo.frame(in: .global)
                                                // 设置预览位置：在图标右侧，垂直居中
                                                store.previewLocation = CGPoint(x: frame.maxX + 110, y: frame.midY)
                                                store.previewOffset = .zero
                                                
                                                withAnimation(.spring(response: 0.2)) {
                                                    store.previewRecord = record
                                                }
                                            }
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.2)) {
                                            // 只有当当前预览的是这条记录时才清除，防止快速移动导致闪烁
                                            if store.previewRecord?.id == record.id {
                                                store.previewRecord = nil
                                            }
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let url = getFileURL(from: record) {
                                        FileOpener.open(url: url, preferredEditor: PreferencesManager.shared.preferredEditor)
                                    }
                                }
                        }
                        .frame(width: 16, height: 16)
                    } else if record.type != .text {
                        // 非图片类型的图标
                        LucideView(name: typeIconLucide, size: 10, color: .themeTextTertiary)
                            .frame(width: 16, height: 16)
                            .background(Color.themeHoverLight)
                            .cornerRadius(3)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let url = getFileURL(from: record) {
                                    FileOpener.open(url: url, preferredEditor: PreferencesManager.shared.preferredEditor)
                                }
                            }
                    }

                    // Title
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .medium)) // text-sm font-medium
                        .foregroundColor(record.aiStatus == "pending" ? Color.themeStatusPending : Color.themeTextPrimary)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                    
                    // Status Icon (AI/Star)
                    if let statusIcon = statusIconLucide {
                        LucideView(name: statusIcon, size: 12, color: statusColor)
                    }
                }

                // Meta Info
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(formattedDate)
                        
                        if let app = record.sourceApp {
                            Rectangle().fill(Color.themeGray700).frame(width: 1, height: 10)
                            HStack(spacing: 4) {
                                LucideView(name: .appWindowMac, size: 10, color: .themeTextTertiary)
                                Text(app)
                                    .lineLimit(1)
                            }
                        }

                        // URL类型：显示可点击链接（直接在浏览器打开）
                        if record.type == .url, let url = URL(string: record.content) {
                            Rectangle().fill(Color.themeGray700).frame(width: 1, height: 10)
                            HStack(spacing: 4) {
                                LucideView(name: .link, size: 10, color: .themeBlue400)
                                Text(url.host ?? record.content)
                                    .lineLimit(1)
                                    .frame(maxWidth: 120, alignment: .leading)
                                    .foregroundColor(.themeBlue400)
                            }
                            .onTapGesture {
                                NSWorkspace.shared.open(url)
                            }
                            .pointingHandCursor()
                            .help("在浏览器中打开: \(record.content)")
                        } else if let urlString = record.sourceUrl, let url = URL(string: urlString) {
                            Rectangle().fill(Color.themeGray700).frame(width: 1, height: 10)
                            HStack(spacing: 4) {
                                LucideView(name: .link, size: 10, color: .themeTextTertiary)
                                if url.isFileURL {
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                        .frame(maxWidth: 120, alignment: .leading)
                                } else {
                                    Text(url.host ?? urlString)
                                        .lineLimit(1)
                                        .frame(maxWidth: 100, alignment: .leading)
                                }
                            }
                            .onTapGesture {
                                if let finalUrl = getFileURL(from: record) {
                                    FileOpener.open(url: finalUrl, preferredEditor: PreferencesManager.shared.preferredEditor)
                                }
                            }
                            .pointingHandCursor()
                            .help(url.isFileURL ? "在编辑器或 Finder 中打开: \(url.path)" : "在浏览器中打开: \(urlString)")
                        }

                        Text("•")

                        Text("\(record.content.count) 字符")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.themeTextTertiary)

                // Tags Row - 在折叠状态显示标签
                if !record.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(record.tags, id: \.self) { tag in
                                Button(action: {
                                    searchTerm = tag
                                    HapticFeedbackManager.shared.lightImpact()
                                }) {
                                    Text(tag)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.themeBlue400)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.themeBlue500.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }
                    .frame(height: 18)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions - 始终显示按钮，提高可用性
            actionButtonsView
                .padding(.trailing, 12)
        }
        .frame(minHeight: 72) // 使用最小高度，允许在内容较多或系统字体变大时伸展
        .padding(.leading, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // 还原：点击卡片任何非功能区仅用于展开/折叠
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedId = isExpanded ? nil : record.id
            }
        }
    }

    private var actionButtonsView: some View {
        HStack(spacing: 6) {
            // 文件夹同步按钮
            if record.type == .folder {
                let isSynced = record.sourceUrl?.contains("SyncedFolders") ?? false
                IconButton(
                    icon: isSynced ? .refreshCw : .cloudDownload,
                    color: isSynced ? .themeStatusSuccess : .themeTextSecondary
                ) {
                    store.syncFolder(record)
                }
                .help(isSynced ? "已同步到本地" : "同步文件夹到本地")
            }

            IconButton(icon: record.starred ? .star : .starOff, color: record.starred ? .themeYellow500 : .themeTextSecondary) {
                store.toggleStar(record)
            }
            // 单独总结按钮 - 根据状态显示不同样式
            if !record.skipAI {
                summarizeButton
            }

            if deleteCountdown > 0 {
                cancelButton
            } else {
                IconButton(icon: .trash2, color: .themeTextSecondary) {
                    startDeleteTimer()
                }
                .help("删除此消息")
            }

            // 展开/收起按钮始终显示
            expandCollapseButton
        }
        .opacity(hovering || isExpanded ? 1.0 : 0.8) // 减少透明度变化
        .scaleEffect(hovering || isExpanded ? 1.0 : 0.95) // 减少缩放幅度
        .animation(.easeOut(duration: 0.15), value: hovering) // 减少动画时长
    }

    private var summarizeButton: some View {
        Button(action: {
            generateIndividualSummary()
        }) {
            Group {
                if record.aiStatus == "fail" {
                    // 失败状态：显示警告图标
                    LucideView(name: .alertTriangle, size: 14, color: .themeRed500)
                        .frame(width: 24, height: 24)
                        .background(Color.themeRed500.opacity(0.1))
                        .clipShape(Circle())
                } else {
                    // 正常或处理中状态
                    LucideView(name: .sparkles, size: 14, color: record.aiStatus == "pending" ? .themeStatusPending : .themeBlue500)
                        .frame(width: 24, height: 24)
                        .background(Color.themeHoverLight)
                        .clipShape(Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .focusable(false)
        .help(record.aiStatus == "fail" ? "总结失败，点击重试" : "单独总结此消息")
    }

    private var cancelButton: some View {
        Button(action: {
            cancelDelete()
        }) {
            HStack(spacing: 4) {
                LucideView(name: .rotateCcw, size: 14, color: .themeGray400)
                Text("\(deleteCountdown)s")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.themeTextSecondary)
            }
            .frame(width: 48, height: 24)
            .background(Color.themeHoverMedium)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("撤回删除")
    }

    private var expandCollapseButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedId = nil
                } else {
                    expandedId = record.id
                }
            }
        }) {
            LucideView(name: .chevronRight, size: 14, color: .themeTextSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 24, height: 24)
                .background(Color.themeHoverLight)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var cardExpandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 延迟加载内容，提升展开性能
            if showContent {
                summarySection
                originalContentSection
            }
        }
        .padding(12)
        .padding(.bottom, 20) // 固定底部 padding，防止 shadow 与下一个卡片重叠
        .padding(.top, 0)
        .contentShape(Rectangle()) // 确保整个区域（包括 padding）都能捕获点击，防止穿透
        .animation(.easeOut(duration: 0.2), value: showContent) // 局部动画，只针对内容显示
        .onAppear {
            onAppearAction()
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if record.summary != nil || record.aiStatus == "fail" {
            VStack(alignment: .leading, spacing: 8) {
                summaryHeader
                summaryBody
                keywordsView

                // 当有总结且原文折叠时，显示"显示原文"按钮
                if record.summary != nil && !showOriginalContent {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showOriginalContent = true
                            }
                            // 发送通知，让父视图知道原文展开状态变化
                            NotificationCenter.default.post(
                                name: Notification.Name("OriginalContentToggled"),
                                object: ["recordId": record.id, "isExpanded": true]
                            )
                        }) {
                            HStack(spacing: 4) {
                                LucideView(name: .eye, size: 10, color: .themeTextSecondary)
                                Text("显示原文")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.themeTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.themeHoverLight)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    private var summaryHeader: some View {
        HStack {
            HStack(spacing: 4) {
                LucideView(name: .sparkles, size: 10, color: record.aiStatus == "fail" ? .themeRed500 : .themePurple500)
                Text("AI 智能总结")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(record.aiStatus == "fail" ? .themeRed500 : .themePurple500)
            .textCase(.uppercase)
            Spacer()
            if let s = record.summary {
                copySummaryButton(s)
            } else if record.aiStatus == "fail" {
                retrySummaryButton
            }
        }
    }

    private func copySummaryButton(_ s: String) -> some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
            HapticFeedbackManager.shared.lightImpact()
            store.postToast("已复制总结", type: "success")
        }) {
            HStack(spacing: 4) {
                LucideView(name: .copy, size: 10, color: .themePurple500)
                Text("复制总结")
            }
            .font(.system(size: 10))
            .foregroundColor(.themePurple500)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.themePurple500.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var retrySummaryButton: some View {
        Button(action: {
            store.resummarize(record: record)
        }) {
            HStack(spacing: 4) {
                LucideView(name: .refreshCw, size: 10, color: .themeRed500)
                Text("重试")
            }
            .font(.system(size: 10))
            .foregroundColor(.themeRed500)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.themeRed500.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var summaryBody: some View {
        SelectableTextView(
            text: record.summary ?? "提炼失败",
            fontSize: 12,
            isMonospaced: false,
             textColor: NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 0.8), // themePurple400 opacity 0.8
             inset: CGSize(width: 10, height: 10),
             showScrollbar: false // 总结区域不显示滚动条
          )
          .frame(minHeight: 65, maxHeight: 250) // 调高最小高度，确保 2-3 行文字无需滚动即可完整显示
        .background(Color.themePurple500.opacity(0.1))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeShadowPurple, lineWidth: 1).allowsHitTesting(false))
    }

    private var keywordsView: some View {
        Group {
            if !record.keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(record.keywords, id: \.self) { keyword in
                            Button(action: {
                                searchTerm = keyword
                                HapticFeedbackManager.shared.lightImpact()
                            }) {
                                Text(keyword)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.themeHoverLight)
                                    .foregroundColor(.themeGray400)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var originalContentSection: some View {
        if record.summary == nil || showOriginalContent {
            VStack(alignment: .leading, spacing: 0) {
                originalContentHeader
                originalContentBody
            }
            .id("original-content-\(record.id.uuidString)") // 添加 ID 以支持滚动定位
        }
    }

    private var originalContentHeader: some View {
        HStack {
            HStack(spacing: 4) {
                LucideView(name: .rss, size: 10, color: .themeTextTertiary)
                Text("原文内容")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.themeTextTertiary)
            .textCase(.uppercase)
            Spacer()
        }
    }

    private var originalContentBody: some View {
        let isImage = record.type == .image || record.type == .screenshot

        return ZStack(alignment: .topLeading) {
            // 原文内容
            VStack(alignment: .leading, spacing: 12) {
                if let urlString = record.sourceUrl,
                   let url = FileCoordinator.shared.resolveVirtualPath(urlString),
                   isImage {
                    // 图片大图预览
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(8)
                                .onTapGesture {
                                    NSWorkspace.shared.open(url)
                                }
                                .help("点击在外部查看")
                        case .failure:
                            Text("图片加载失败")
                                .foregroundColor(.themeStatusError)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.themePanel)
                    .cornerRadius(8)
                }

                SelectableTextView(
                    text: record.content,
                    fontSize: 11,
                    isMonospaced: true,
                    textColor: NSColor(red: 209/255, green: 213/255, blue: 221/255, alpha: 1.0), // themeGray300
                    inset: CGSize(width: 8, height: 8), // 稍微减小内边距，给内容更多空间
                    showScrollbar: true // 原文长，需要滚动条
                )
                .frame(minHeight: 350, maxHeight: 650) // 增加最小高度到 350pt，确保内容显示更充分
                .background(Color.themeBackground) // 使用更深的背景色，使 ASCII 艺术更清晰
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.themeBorder, lineWidth: 1).allowsHitTesting(false))
                // 悬浮按钮：折叠原文 + 复制
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        // 折叠原文按钮（仅在有 summary 且原文展开时显示）
                        if record.summary != nil && showOriginalContent {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showOriginalContent = false
                                }
                                // 发送通知，让父视图更新间距
                                NotificationCenter.default.post(
                                    name: Notification.Name("OriginalContentToggled"),
                                    object: ["recordId": record.id, "isExpanded": false]
                                )
                                // 发送通知，让父视图滚动到卡片顶部
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("ScrollToCard"),
                                        object: ["recordId": record.id.uuidString]
                                    )
                                }
                            }) {
                                LucideView(name: .eyeOff, size: 12, color: .themeTextSecondary)
                                    .frame(width: 24, height: 24)
                                    .background(Color.themeBackground.opacity(0.9))
                                    .cornerRadius(4)
                                    .shadow(color: Color.themeShadowHeavy, radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .help("折叠原文")
                        }

                        // 复制按钮（始终显示）
                        Button(action: {
                            let isImageType = record.type == .image || record.type == .screenshot
                            if isImageType, let urlString = record.sourceUrl, let url = FileCoordinator.shared.resolveVirtualPath(urlString) {
                                // 复制图片文件到剪贴板
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([url as NSURL])
                                store.postToast("已复制图片", type: "success")
                            } else {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.content, forType: .string)
                                store.postToast("已复制原文", type: "success")
                            }
                            HapticFeedbackManager.shared.lightImpact()
                        }) {
                            LucideView(name: .copy, size: 12, color: .themeTextSecondary)
                                .frame(width: 24, height: 24)
                                .background(Color.themeBackground.opacity(0.9))
                                .cornerRadius(4)
                                .shadow(color: Color.themeShadowHeavy, radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help(isImage ? "复制图片" : "复制原文")
                    }
                    .padding(6)
                }
            }
            // GeometryReader 监听布局变化
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            // 初次出现时发送通知
                            sendLayoutNotification(height: geometry.size.height)
                        }
                        .onChange(of: geometry.size.height) { newHeight in
                            // 高度变化时发送通知（包括展开/折叠原文）
                            sendLayoutNotification(height: newHeight)
                        }
                }
            )
        }
    }

    // 发送布局完成通知
    private func sendLayoutNotification(height: CGFloat) {
        // 只在原文已展开且有有效高度时发送
        guard showOriginalContent && height > 100 else { return }

        // 延迟发送，确保 SwiftUI 完成布局计算
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: Notification.Name("OriginalContentLayoutComplete"),
                object: [
                    "recordId": record.id.uuidString,
                    "height": height
                ]
            )
        }
    }

    private func onAppearAction() {
        // 如果有总结，默认折叠原文
        if record.summary != nil {
            showOriginalContent = false
        }

        // 延迟加载内容，提升展开性能
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showContent = true
            }
        }
    }
}

/// 用于拖拽感应的三角形形状
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension RecordCardView {
    /// 实现Equatable协议，减少不必要的重绘
    static func == (lhs: RecordCardView, rhs: RecordCardView) -> Bool {
        lhs.record == rhs.record &&
        lhs.isExpanded == rhs.isExpanded &&
        lhs.searchTerm == rhs.searchTerm &&
        lhs.deleteCountdown == rhs.deleteCountdown
    }
}

// MARK: - Private Extensions

private extension RecordCardView {
    /// 为当前记录生成单独的AI总结
    func generateIndividualSummary() {
        // 如果已经在处理中，不重复请求
        guard record.aiStatus != "pending" else { return }

        // 更新状态为处理中
        store.updateRecordAI(
            id: record.id,
            title: "AI 正在分析内容...",
            summary: nil,
            confidence: 0,
            aiStatus: "pending"
        )

        // 调用AI服务生成总结
        let existingTags = store.records.flatMap { $0.tags }
        let uniqueTags = Array(Set(existingTags)).sorted()

        store.ai?.summarizeSingle(contextId: record.id.uuidString, record.content, existingTags: uniqueTags) { [weak store] (result: Result<SummaryResult, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let summaryResult):
                    let title = summaryResult.title
                    let summary = summaryResult.summary
                    let confidence = summaryResult.confidence
                    store?.updateRecordAI(
                        id: record.id,
                        title: title,
                        summary: summary,
                        confidence: confidence,
                        aiStatus: "success",
                        tags: summaryResult.tags,
                        keywords: summaryResult.keywords
                    )
                    store?.postToast("总结已生成", type: "success")
                case .failure(let error):
                    store?.updateRecordAI(
                        id: record.id,
                        title: "提炼失败",
                        summary: nil,
                        confidence: 0,
                        aiStatus: "fail"
                    )
                    store?.postToast("总结生成失败: \(error.localizedDescription)", type: "error")
                }
            }
        }
    }

    /// 开始删除倒计时
    func startDeleteTimer() {
        deleteCountdown = 3
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if deleteCountdown > 1 {
                deleteCountdown -= 1
            } else {
                deleteTimer?.invalidate()
                deleteTimer = nil
                deleteCountdown = 0
                store.delete(record)
            }
        }
    }

    /// 撤回删除
    func cancelDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        deleteCountdown = 0
    }

    // 缓存计算结果，避免重复计算
    var displayTitle: String {
        // 使用更高效的条件判断顺序
        switch record.aiStatus {
        case "fail":
            return "提炼失败"
        case "pending":
            return "AI 正在分析内容..."
        default:
            if let t = record.title, !t.isEmpty { return t }
            
            // 如果没有标题，尝试从路径中解析文件名
            if let urlString = record.sourceUrl,
               let url = FileCoordinator.shared.resolveVirtualPath(urlString) {
                let fileName = url.lastPathComponent
                if !fileName.isEmpty {
                    if record.type == .folder, let count = record.fileCount {
                        return "\(fileName) (\(count) 个文件)"
                    }
                    return fileName
                }
            }
            
            // 兜底显示逻辑
            switch record.type {
            case .folder: return "文件夹"
            case .file: return "文件"
            case .image: return "照片"
            case .screenshot: return "截图"
            default:
                return record.content.count > 30 ? String(record.content.prefix(30)) + "..." : record.content
            }
        }
    }

    /// 格式化日期显示
    /// - 24小时内：显示时间
    /// - 24小时-30天：显示 n天前
    /// - 30天以上：显示 yyyy-MM-dd
    var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()

        // 计算天数差异（使用 startOfDay 确保精确到天）
        let startOfNow = calendar.startOfDay(for: now)
        let startOfCreated = calendar.startOfDay(for: record.createdAt)
        let dayComponents = calendar.dateComponents([.day], from: startOfCreated, to: startOfNow)
        let days = dayComponents.day ?? 0

        // 计算小时差异
        let hourComponents = calendar.dateComponents([.hour], from: record.createdAt, to: now)
        let hours = hourComponents.hour ?? 0

        if hours < 24 {
            // 24小时内显示时间
            return record.createdAt.formatted(date: .omitted, time: .shortened)
        } else if days < 30 {
            // 24小时以上且30天以内
            return "\(days)天前"
        } else {
            // 30天以上显示具体日期
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: record.createdAt)
        }
    }

    var typeIconLucide: IconName {
        record.type.icon
    }

    var statusIconLucide: IconName? {
        // 1. 优先显示总结状态
        if record.summary != nil { return .sparkles }
        
        // 2. 其次显示 AI 处理状态
        switch record.aiStatus {
        case "pending": return .zap
        case "fail": return .alertTriangle
        default:
            return nil
        }
    }

    var statusColor: Color {
        // 如果有总结，显示紫色
        if record.summary != nil { return .themePurple500 }
        
        // 否则根据 AI 状态显示颜色
        switch record.aiStatus {
        case "pending": return .themeYellow500
        case "fail": return .themeRed500
        default:
            // 如果是已收藏但没有总结/处理中的状态，图标区域不显示，所以这里返回默认灰色
            return .themeGray500
        }
    }

    var statusText: String {
        // 使用更高效的条件判断顺序
        if record.summary != nil { return "已总结" }
        switch record.aiStatus {
        case "pending": return "提炼中..."
        case "fail": return "提炼失败"
        default:
            return record.title != nil ? "仅标题" : "原始记录"
        }
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
