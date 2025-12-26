import SwiftUI

/// 单条记录卡片视图
struct RecordCardView: View, Equatable {
    let record: Record
    @Binding var expandedId: UUID?
    @Binding var searchTerm: String
    let store: RecordStore
    @State private var hovering = false
    @State private var showOriginalContent = false
    @State private var showContent = false // 控制内容延迟显示
    @State private var showFullContent = false // 控制是否显示完整内容

    // 删除撤回逻辑
    @State private var deleteCountdown = 0
    @State private var deleteTimer: Timer? = nil

    // 缓存计算结果，避免重复计算
    private var isExpanded: Bool {
        expandedId == record.id
    }

    // 使用@ViewBuilder优化条件渲染
    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            if isExpanded {
                cardExpandedContent
            }
        }
        // 简化背景和边框，减少重绘
        .background(Color.themeItem)
        .cornerRadius(8) // rounded-lg
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? Color.themeFocused : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        )
        // 只在展开状态时应用阴影，减少性能开销
        .shadow(color: isExpanded ? Color.themeShadowMedium : .clear, radius: 10, x: 0, y: 2)
        .animation(.easeOut(duration: 0.2), value: isExpanded) // 减少动画时长
        .onChange(of: isExpanded) { expanded in
            // 当折叠时，重置内容显示状态，优化性能
            if !expanded {
                showContent = false
                showFullContent = false
            }
        }
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    // Type Icon
                    LucideView(name: typeIconLucide, size: 14, color: .themeTextSecondary)
                        .frame(width: 18, height: 18)
                        .background(Color.themeHoverLight)
                        .cornerRadius(4)

                    // Title
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .medium)) // text-sm font-medium
                        .foregroundColor(record.aiStatus == "pending" ? Color.themeStatusPending : Color.themeTextPrimary)
                        .lineLimit(1)
                    
                    // Status Icon (AI/Star)
                    if let statusIcon = statusIconLucide {
                        LucideView(name: statusIcon, size: 12, color: statusColor)
                    }
                }

                // Meta Info
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(formattedDate)
                        Rectangle().fill(Color.themeGray700).frame(width: 2, height: 10)
                        Text("\(record.content.count) 字符")

                        if let app = record.sourceApp {
                            Rectangle().fill(Color.themeGray700).frame(width: 2, height: 10)
                            HStack(spacing: 4) {
                                LucideView(name: .appWindowMac, size: 10, color: .themeTextTertiary)
                                Text(app)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        if let urlString = record.sourceUrl, let url = URL(string: urlString) {
                            Rectangle().fill(Color.themeGray700).frame(width: 2, height: 10)
                            HStack(spacing: 4) {
                                LucideView(name: .link, size: 10, color: .themeTextTertiary)
                                Text(url.isFileURL ? url.lastPathComponent : urlString)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .onTapGesture {
                                if url.isFileURL {
                                    FileOpener.open(url: url, preferredEditor: PreferencesManager.shared.preferredEditor)
                                } else {
                                    NSWorkspace.shared.open(url)
                                }
                                HapticFeedbackManager.shared.lightImpact()
                            }
                            .pointingHandCursor()
                            .help(url.isFileURL ? "在 Finder 中显示: \(url.path)" : "在浏览器中打开: \(urlString)")
                        }

                        if !record.tags.isEmpty {
                            Rectangle().fill(Color.themeGray700).frame(width: 2, height: 10)
                            HStack(spacing: 4) {
                                ForEach(record.tags.prefix(3), id: \.self) { tag in
                                    TagView(text: tag, color: .themeBlue400, bgColor: .themeActive) {
                                        searchTerm = tag
                                    }
                                }
                            }
                        }
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.themeTextTertiary)

                // Keywords Row (New)
                if !record.keywords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(record.keywords.prefix(10), id: \.self) { keyword in
                                let displayKeyword = keyword.hasPrefix("#") ? keyword : "#\(keyword)"
                                Text(displayKeyword)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.themePurple400)
                                    .onTapGesture {
                                        searchTerm = keyword
                                    }
                                    .pointingHandCursor()
                            }
                        }
                    }
                    .frame(height: 14)
                }
            }

            Spacer()

            // Actions - 始终显示按钮，提高可用性
            actionButtonsView
        }
        .padding(12) // p-3
        .contentShape(Rectangle())
        .onTapGesture {
            // 使用更快的动画减少卡顿
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedId = isExpanded ? nil : record.id
            }
        }
    }

    private var actionButtonsView: some View {
        HStack(spacing: 6) {
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
        VStack(alignment: .leading, spacing: 0) {
            // Expanded Content Area
            VStack(alignment: .leading, spacing: 12) {
                // 延迟加载内容，提升展开性能
                if showContent {
                    summarySection
                    originalContentSection
                    toggleOriginalContentButton
                }
            }
            .padding(12)
            .padding(.top, 0)
        }
        .onAppear {
            onAppearAction()
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var summarySection: some View {
        if record.summary != nil || record.aiStatus == "fail" {
            VStack(alignment: .leading, spacing: 8) {
                summaryHeader
                summaryBody
                keywordsView
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
            VStack(alignment: .leading, spacing: 8) {
                originalContentHeader
                originalContentBody
            }
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
            copyOriginalButton
        }
    }

    private var copyOriginalButton: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.content, forType: .string)
            HapticFeedbackManager.shared.lightImpact()
            store.postToast("已复制原文", type: "success")
        }) {
            HStack(spacing: 4) {
                LucideView(name: .copy, size: 10, color: .themeTextSecondary)
                Text("复制原文")
            }
            .font(.system(size: 10))
            .foregroundColor(.themeTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.themeHoverLight)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var originalContentBody: some View {
        SelectableTextView(
            text: record.content,
            fontSize: 11,
            isMonospaced: true,
             textColor: NSColor(red: 209/255, green: 213/255, blue: 221/255, alpha: 1.0), // themeGray300
             showScrollbar: true // 原文长，需要滚动条
          )
          .frame(minHeight: 250, maxHeight: 650) // 进一步调高，提供更好视野，减少滚动频率
        .background(Color.themePanel)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.themeBorder, lineWidth: 1).allowsHitTesting(false))
    }

    @ViewBuilder
    private var toggleOriginalContentButton: some View {
        if record.summary != nil {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showOriginalContent.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        LucideView(name: showOriginalContent ? .eyeOff : .eye, size: 10, color: .themeTextSecondary)
                        Text(showOriginalContent ? "隐藏原文" : "显示原文")
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

    /// 实现Equatable协议，减少不必要的重绘
    static func == (lhs: RecordCardView, rhs: RecordCardView) -> Bool {
        return lhs.record.id == rhs.record.id &&
               lhs.record.content == rhs.record.content &&
               lhs.record.title == rhs.record.title &&
               lhs.record.summary == rhs.record.summary &&
               lhs.record.starred == rhs.record.starred &&
               lhs.record.aiStatus == rhs.record.aiStatus &&
               lhs.record.tags == rhs.record.tags &&
               lhs.record.keywords == rhs.record.keywords &&
               lhs.isExpanded == rhs.isExpanded &&
               lhs.searchTerm == rhs.searchTerm
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
            if record.type == .folder { return "文件夹" }
            if record.type == .file { return "文件" }
            return record.content.count > 30 ? String(record.content.prefix(30)) + "..." : record.content
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
        switch record.type {
        case .folder: return .folder
        case .file: return .paperclip
        case .text: return .fileText
        case .image: return .image
        case .video: return .video
        }
    }

    var statusIconLucide: IconName? {
        // 1. 优先显示星标图标
        if record.starred { return .star }

        // 2. 其次显示总结状态
        if record.summary != nil { return .sparkles }
        
        switch record.aiStatus {
        case "pending": return .zap
        case "fail": return .alertTriangle
        default:
            return nil
        }
    }

    var statusColor: Color {
        // 1. 优先显示收藏颜色
        if record.starred { return .themeYellow500 }

        if record.summary != nil { return .themePurple500 }
        switch record.aiStatus {
        case "pending": return .themeYellow500
        case "fail": return .themeRed500
        default:
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
