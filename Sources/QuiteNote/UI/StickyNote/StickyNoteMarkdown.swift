import AppKit

// MARK: - 便利贴 Markdown ⇄ 富文本
//
// 纯函数，不依赖 NSTextView / 窗口，所有坐标都是 UTF-16 单元（与 NSTextStorage / NSRange 同口径）。

/// 便利贴的标记语言转换器。
///
/// 标记语法（保持兼容，不新增语法）：
/// - 加粗 `**文字**`、删除线 `~~文字~~`、下划线 `<u>文字</u>`、文字颜色 `[c:hex]文字[/c]`
/// - 待办 `- [ ] 文字` / `- [x] 文字`：渲染成单字符图标 ☐ / ☑（带 `isTodoIcon` 属性）。
///   不要求出现在行首，行中间出现同样渲染。
///
/// 核心不变量：`serialize(render(x)) == x`（对规范写法的 x）。下面几种写法会在第一轮被归一化，
/// 之后保持稳定（幂等）：`[c:#60A5FA]` 去掉 `#`、`- [ ]文字` 补成 `- [ ] 文字`、裸 ☐ / ☑ 转成
/// 待办标记、同一位置同时开始的多种格式按「颜色 > 下划线 > 删除线 > 加粗」重排、相邻的同格式区间合并。
///
/// 行内标记可以跨越单个换行，但不能跨空行（空行 = 空的或只有空格/制表符的行）；没闭合的标记按字面输出。
enum StickyNoteMarkdown {

    // MARK: - 属性键（运行期键名保持不变）

    static let boldKey = NSAttributedString.Key("isBold")
    static let strikethroughKey = NSAttributedString.Key("isStrikethrough")
    static let underlineKey = NSAttributedString.Key("isUnderline")
    static let colorKey = NSAttributedString.Key("customColor")
    static let todoIconKey = NSAttributedString.Key("isTodoIcon")

    // MARK: - 基础样式（全编辑器唯一出处）

    static let baseFontSize: CGFloat = 12
    /// 图标比正文大 2pt（沿用原视觉）
    static let iconFontSize: CGFloat = baseFontSize + 2
    static let lineSpacing: CGFloat = 4
    static let lineHeight: CGFloat = 18

    static let baseFont: NSFont = NSFont.systemFont(ofSize: baseFontSize)
    static let boldFont: NSFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
    static let iconFont: NSFont = NSFont.systemFont(ofSize: iconFontSize)
    static let boldIconFont: NSFont = NSFontManager.shared.convert(iconFont, toHaveTrait: .boldFontMask)
    static let textColor: NSColor = .white
    /// 未勾选图标：次要文字色
    static let todoUncheckedColor: NSColor = .themeGray400
    /// 已勾选图标：实时输入、重建渲染、点击切换三处统一用这一个颜色
    static let todoCheckedColor: NSColor = .themeGreen400
    /// 图标后的视觉间距。渲染时吞掉了 `- [ ]` 后面那个空格，这里用一个空格的宽度补回来，
    /// 所以「刚敲出来」和「重开后」两种形态看起来一样宽。
    static let todoIconGap: CGFloat = {
        let width = (" " as NSString).size(withAttributes: [.font: baseFont]).width
        return width > 0.5 ? width : 3
    }()
    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }()

    /// 基础显示 / 输入属性
    static var baseAttributes: [NSAttributedString.Key: Any] {
        displayAttributes(bold: false, strikethrough: false, underline: false, colorHex: nil, isTodoIcon: false, checked: false)
    }

    static let uncheckedIcon = "☐"
    static let checkedIcon = "☑"
    static let uncheckedIconUnit: unichar = 0x2610
    static let checkedIconUnit: unichar = 0x2611

    /// 嵌套层数上限：超过的标记按字面输出（防止极端输入把递归栈打穿）
    private static let maxNestingDepth = 128

    // MARK: - 渲染：Markdown → 富文本

    static func render(_ markdown: String) -> NSAttributedString {
        let chars = Array(markdown.utf16)
        guard !chars.isEmpty else { return NSAttributedString(string: "") }
        let renderer = Renderer(chars: chars, lines: LineIndex(chars))
        renderer.renderRegion(0, chars.count, style: Renderer.Style(), depth: 0)
        return renderer.build()
    }

    /// 去掉标记后的可见文字。待办图标保留为「☐ / ☑ + 空格」。
    /// 没闭合的标记在这里同样是字面文字（与编辑器里看到的一致）。
    static func plainText(_ markdown: String) -> String {
        let chars = Array(render(markdown).string.utf16)
        var out: [unichar] = []
        out.reserveCapacity(chars.count + 8)
        for (index, unit) in chars.enumerated() {
            out.append(unit)
            if isTodoIconUnit(unit), index + 1 < chars.count, !isNewline(chars[index + 1]) {
                out.append(0x20)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    // MARK: - 序列化：富文本 → Markdown

    /// 「区间 + 栈」：先求出四种格式各自的生效区间，再按位置扫描——区间起点写开标记、终点写闭标记。
    /// 外层先结束而内层还在延续时，先闭内层、闭外层、再重开内层，所以交叉重叠也能输出正确的嵌套。
    /// 同一个落点上开始的格式固定按 颜色 > 下划线 > 删除线 > 加粗 嵌套。
    static func serialize(_ attributed: NSAttributedString) -> String {
        let length = attributed.length
        guard length > 0 else { return "" }

        // 1. 状态分段：相邻且四种格式状态相同（颜色值也相同）的 run 合并成一段
        var segmentStarts: [Int] = []
        var segmentStates: [FormatState] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { attrs, range, _ in
            let state = FormatState(attrs)
            if segmentStates.last != state {
                segmentStarts.append(range.location)
                segmentStates.append(state)
            }
        }

        let chars = Array(attributed.string.utf16)
        guard chars.count == length else { return attributed.string }

        var out: [unichar] = []
        out.reserveCapacity(length + 32)
        var stack: [Format] = []
        var textStart = 0

        func emitText(upTo end: Int) {
            var index = textStart
            var plainStart = textStart
            while index < end {
                let unit = chars[index]
                if isTodoIconUnit(unit) {
                    if index > plainStart { out.append(contentsOf: chars[plainStart..<index]) }
                    // 带 isTodoIcon 属性的图标和裸 ☐ / ☑ 都输出成待办标记
                    out.append(contentsOf: (unit == checkedIconUnit ? "- [x]" : "- [ ]").utf16)
                    // 渲染时吞掉了标记后的那个分隔空格/制表符：图标后面还有内容时补回一个空格。
                    // 图标后面本来就跟着空格的（原文写了两个）照样补，剩下的那个是正文
                    if index + 1 < length, !isNewline(chars[index + 1]) { out.append(0x20) }
                    plainStart = index + 1
                }
                index += 1
            }
            if plainStart < end { out.append(contentsOf: chars[plainStart..<end]) }
            textStart = end
        }

        for (index, state) in segmentStates.enumerated() {
            let previous = index > 0 ? segmentStates[index - 1] : FormatState.none
            var closes: [Format] = []
            var opens: [Format] = []
            for format in Format.allCases {
                let wasOn = previous.has(format)
                let isOn = state.has(format)
                if wasOn != isOn {
                    if isOn { opens.append(format) } else { closes.append(format) }
                }
            }
            // 相邻两段颜色不同：先闭合再重新打开（hex 按原文比较，大小写也原样保留）
            if let previousHex = previous.colorHex, let currentHex = state.colorHex, previousHex != currentHex {
                closes.append(.color)
                opens.append(.color)
            }
            if !closes.isEmpty {
                // 从栈顶往下摘到要闭合的格式为止：路上被摘下来的是「还要延续」的内层，记下来稍后重开
                var remaining = closes
                var toReopen: [Format] = []
                while let top = stack.last, !remaining.isEmpty {
                    stack.removeLast()
                    out.append(contentsOf: top.closeMarker.utf16)
                    if let position = remaining.firstIndex(of: top) {
                        remaining.remove(at: position)
                    } else {
                        toReopen.append(top)
                    }
                }
                opens.insert(contentsOf: toReopen, at: 0)
            }
            if !opens.isEmpty {
                opens.sort { $0.rawValue < $1.rawValue }
                let colorHex = state.colorHex ?? ""
                for format in opens {
                    out.append(contentsOf: format.openMarker(colorHex: colorHex).utf16)
                    stack.append(format)
                }
            }
            emitText(upTo: index + 1 < segmentStarts.count ? segmentStarts[index + 1] : length)
        }
        while let format = stack.popLast() {
            out.append(contentsOf: format.closeMarker.utf16)
        }
        return String(decoding: out, as: UTF16.self)
    }

    // MARK: - 颜色

    /// 解析标记里的 hex：3 / 4 / 6 / 8 位（RGB / RGBA / RRGGBB / RRGGBBAA），可带 `#`，大小写不敏感。
    /// 3 / 4 位缩写按 CSS 规则展开（每一位重复一次）；位数不对或含非十六进制字符返回 nil。
    static func color(fromHex raw: String) -> NSColor? {
        var scalars = Array(raw.unicodeScalars)
        if scalars.first == "#" { scalars.removeFirst() }
        guard [3, 4, 6, 8].contains(scalars.count), scalars.allSatisfy({ $0.value <= 0xFFFF && isHexDigit(unichar($0.value)) }) else { return nil }
        var text = String(String.UnicodeScalarView(scalars))
        if scalars.count == 3 || scalars.count == 4 {
            text = scalars.map { "\($0)\($0)" }.joined()
        }
        return NSColor(hex: text)
    }

    /// 宽松模式（失焦蒙层的项目名用）：去掉文本里所有颜色标记记号 `[c:…]` 与 `[/c]`——
    /// 不要求成对、也不要求 hex 合法，蒙层上不该露出标记。同时返回第一个合法的 hex。
    static func strippingColorMarkers(_ text: String) -> (text: String, firstHex: String?) {
        let chars = Array(text.utf16)
        var out: [unichar] = []
        out.reserveCapacity(chars.count)
        var firstHex: String? = nil
        var index = 0
        while index < chars.count {
            if chars[index] == 0x5B, index + 1 < chars.count {
                if chars[index + 1] == 0x2F {                                   // "[/c]"
                    if index + 4 <= chars.count, chars[index + 2] == 0x63, chars[index + 3] == 0x5D {
                        index += 4
                        continue
                    }
                } else if chars[index + 1] == 0x63, index + 2 < chars.count, chars[index + 2] == 0x3A {   // "[c:"
                    // [c:#RRGGBBAA] 括号里最长 9 个单元；找不到 12 个单元以内的 "]" 就当普通文字
                    var close = index + 3
                    while close < chars.count, close - (index + 3) <= 9, chars[close] != 0x5D { close += 1 }
                    if close < chars.count, chars[close] == 0x5D {
                        let inner = String(decoding: chars[(index + 3)..<close], as: UTF16.self)
                        if firstHex == nil, color(fromHex: inner) != nil {
                            firstHex = inner.hasPrefix("#") ? String(inner.dropFirst()) : inner
                        }
                        index = close + 1
                        continue
                    }
                }
            }
            out.append(chars[index])
            index += 1
        }
        return (String(decoding: out, as: UTF16.self), firstHex)
    }

    /// 从 `at` 起读一个颜色开始标记 `[c:hex]`（可带 `#`）。位数不合法的不算标记——
    /// 这样 `[c:12345]` 会原样留在正文里，而不是被静默删掉。
    private static func colorStartMarker(in chars: [unichar], at location: Int, limit: Int) -> (hex: String, length: Int)? {
        // chars[location] == "["
        var index = location + 1
        guard index + 1 < limit, chars[index] == 0x63, chars[index + 1] == 0x3A else { return nil }   // "c:"
        index += 2
        if index < limit, chars[index] == 0x23 { index += 1 }                                     // "#"
        let digitStart = index
        while index < limit, isHexDigit(chars[index]) { index += 1 }
        let digitCount = index - digitStart
        guard digitCount == 3 || digitCount == 4 || digitCount == 6 || digitCount == 8,
              index < limit, chars[index] == 0x5D else { return nil }                             // "]"
        return (String(decoding: chars[digitStart..<index], as: UTF16.self), index + 1 - location)
    }

    // MARK: - 显示属性

    /// 由「语义属性 + 是否图标」推导出完整的显示属性（唯一出处）。
    static func displayAttributes(
        bold: Bool, strikethrough: Bool, underline: Bool, colorHex: String?,
        isTodoIcon: Bool, checked: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle]

        if bold {
            attrs[boldKey] = true
            attrs[.font] = isTodoIcon ? boldIconFont : boldFont
        } else {
            attrs[.font] = isTodoIcon ? iconFont : baseFont
        }
        if strikethrough {
            attrs[strikethroughKey] = true
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if underline {
            attrs[underlineKey] = true
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        var resolvedColor: NSColor? = nil
        if let colorHex {
            attrs[colorKey] = colorHex
            resolvedColor = color(fromHex: colorHex)
        }
        if isTodoIcon {
            attrs[todoIconKey] = checked
            attrs[.kern] = todoIconGap
            if resolvedColor == nil { resolvedColor = checked ? todoCheckedColor : todoUncheckedColor }
        }
        attrs[.foregroundColor] = resolvedColor ?? textColor
        return attrs
    }

    /// 待办图标的属性：图标样式，并继承所在位置的语义属性（加粗/颜色/删除线/下划线），保证往返恒等。
    static func todoIconAttributes(checked: Bool, inheriting attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        displayAttributes(
            bold: attrs[boldKey] != nil,
            strikethrough: attrs[strikethroughKey] != nil,
            underline: attrs[underlineKey] != nil,
            colorHex: attrs[colorKey] as? String,
            isTodoIcon: true,
            checked: checked
        )
    }

    static func todoIcon(checked: Bool, inheriting attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: checked ? checkedIcon : uncheckedIcon, attributes: todoIconAttributes(checked: checked, inheriting: attrs))
    }

    /// 列表前缀（`- ` / `1. `）这类「行首结构性文字」的属性：基础样式 + 继承语义属性。
    static func linePrefixAttributes(inheriting attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        displayAttributes(
            bold: attrs[boldKey] != nil,
            strikethrough: attrs[strikethroughKey] != nil,
            underline: attrs[underlineKey] != nil,
            colorHex: attrs[colorKey] as? String,
            isTodoIcon: false,
            checked: false
        )
    }

    // MARK: - 实时路径（按键后只处理光标所在段落）

    /// 每次按键后调用，只处理光标所在段落，不全文扫描：
    /// 1. 把段落里手打的 `- [ ]` / `- [x]`（连同其后一个空格/制表符）原地换成待办图标；
    /// 2. 把段落里的属性收敛到规范形态——图标用图标样式，非图标字符用「基础样式 + 语义属性」
    ///    推导出的字体和颜色，顺带清掉从图标泄漏出来的字号、颜色、字距和 `isTodoIcon` 残留。
    /// - Returns:
    ///   - `cursorShift`: 光标位置需要平移的量（UTF-16 单元）
    ///   - `separatorLocation`: 如果刚好在光标前生成了一个待办图标，返回图标之后的位置——
    ///     用户接下来敲的那个分隔空格/制表符属于标记语法，由调用方吸收掉（间距已经用字距表示了）
    @discardableResult
    static func normalizeLiveParagraph(_ storage: NSTextStorage, cursorLocation: Int) -> (cursorShift: Int, separatorLocation: Int?) {
        let length = storage.length
        guard length > 0 else { return (0, nil) }
        let cursor = min(max(0, cursorLocation), length)
        let ns = storage.string as NSString
        let paragraph = ns.lineRange(for: NSRange(location: cursor, length: 0))
        guard paragraph.length > 0 else { return (0, nil) }
        let chars = Array(ns.substring(with: paragraph).utf16)
        let count = chars.count

        // 扫一遍段落：待办标记、已有的图标字符
        var matches: [(start: Int, length: Int, checked: Bool)] = []   // 段落内相对位置
        var existingIcons: [Int] = []
        var index = 0
        while index < count {
            let unit = chars[index]
            if isTodoIconUnit(unit) {
                existingIcons.append(index)
                index += 1
            } else if let todo = todoMarkerUnits(chars, at: index, limit: count) {
                matches.append((index, todo.consumed, todo.checked))
                index += todo.consumed
            } else {
                index += 1
            }
        }

        /// 位置 `position` 之前的标记替换带来的总位移
        func shift(before position: Int) -> Int {
            matches.reduce(0) { $0 + ($1.start + $1.length <= position ? 1 - $1.length : 0) }
        }

        var newCursor = cursor
        var separatorLocation: Int? = nil
        storage.beginEditing()
        defer { storage.endEditing() }

        if !matches.isEmpty {
            // 从后往前替换，前面的坐标不受影响
            for match in matches.reversed() {
                let location = paragraph.location + match.start
                let range = NSRange(location: location, length: match.length)
                let semantic = storage.attributes(at: location, longestEffectiveRange: nil, in: range)
                storage.replaceCharacters(in: range, with: todoIcon(checked: match.checked, inheriting: semantic))
            }
            let cursorLocal = cursor - paragraph.location
            newCursor = paragraph.location + cursorLocal + shift(before: cursorLocal)
            // 光标落在标记内部：落到图标后面
            for match in matches where cursorLocal > match.start && cursorLocal < match.start + match.length {
                newCursor = paragraph.location + match.start + shift(before: match.start) + 1
            }
            // 光标紧跟在刚生成的图标后面
            for match in matches where paragraph.location + match.start + shift(before: match.start) + 1 == newCursor {
                separatorLocation = newCursor
            }
        }

        var icons = existingIcons.map { (location: paragraph.location + $0 + shift(before: $0), checked: chars[$0] == checkedIconUnit) }
        icons.append(contentsOf: matches.map { (location: paragraph.location + $0.start + shift(before: $0.start), checked: $0.checked) })
        icons.sort { $0.location < $1.location }

        let totalShift = shift(before: count)
        converge(storage, range: NSRange(location: paragraph.location, length: count + totalShift), icons: icons)
        return (newCursor - cursor, separatorLocation)
    }

    /// 把一段文本的显示属性收敛到规范形态（工具栏改格式后调用：选区里的图标也能拿到正确的图标样式）。
    static func normalize(_ storage: NSTextStorage, range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let chars = Array((storage.string as NSString).substring(with: range).utf16)
        var icons: [(location: Int, checked: Bool)] = []
        for (offset, unit) in chars.enumerated() where isTodoIconUnit(unit) {
            icons.append((range.location + offset, unit == checkedIconUnit))
        }
        converge(storage, range: range, icons: icons)
    }

    /// 收敛「输入属性」：图标专用的字距和 isTodoIcon 不带到后续输入，字体与颜色由语义属性重新推导。
    static func canonicalTypingAttributes(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attrs
        result.removeValue(forKey: todoIconKey)
        result.removeValue(forKey: .kern)
        let target = displayAttributes(
            bold: attrs[boldKey] != nil,
            strikethrough: attrs[strikethroughKey] != nil,
            underline: attrs[underlineKey] != nil,
            colorHex: attrs[colorKey] as? String,
            isTodoIcon: false,
            checked: false
        )
        for key in syncedAttributeKeys {
            if let wanted = target[key], !attributesEqual(result[key], wanted) {
                result[key] = wanted
            }
        }
        return result
    }

    // MARK: - 实时路径 / 命令路径共用

    /// 收敛时需要和 `displayAttributes` 对齐的键；其中图标专用的两个键在目标是「非图标」时要移除。
    private static let syncedAttributeKeys: [NSAttributedString.Key] = [
        .font, .foregroundColor, .strikethroughStyle, .underlineStyle, .kern, todoIconKey, .paragraphStyle,
    ]
    private static let iconOnlyAttributeKeys: [NSAttributedString.Key] = [.kern, todoIconKey]

    private static func converge(_ storage: NSTextStorage, range: NSRange, icons: [(location: Int, checked: Bool)]) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        var fixes: [(range: NSRange, add: [NSAttributedString.Key: Any], remove: [NSAttributedString.Key])] = []
        var iconIndex = 0
        while iconIndex < icons.count, icons[iconIndex].location < range.location { iconIndex += 1 }

        func record(_ attrs: [NSAttributedString.Key: Any], isIcon: Bool, checked: Bool, start: Int, end: Int) {
            guard let fix = attributeFix(attrs, isIcon: isIcon, checked: checked) else { return }
            fixes.append((NSRange(location: start, length: end - start), fix.add, fix.remove))
        }

        storage.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            let runEnd = NSMaxRange(runRange)
            var segmentStart = runRange.location
            while segmentStart < runEnd {
                let end: Int
                if iconIndex < icons.count, icons[iconIndex].location == segmentStart {
                    record(attrs, isIcon: true, checked: icons[iconIndex].checked, start: segmentStart, end: segmentStart + 1)
                    iconIndex += 1
                    end = segmentStart + 1
                } else {
                    end = iconIndex < icons.count ? min(icons[iconIndex].location, runEnd) : runEnd
                    record(attrs, isIcon: false, checked: false, start: segmentStart, end: end)
                }
                segmentStart = end
            }
        }

        for fix in fixes {
            for key in fix.remove { storage.removeAttribute(key, range: fix.range) }
            if !fix.add.isEmpty { storage.addAttributes(fix.add, range: fix.range) }
        }
    }

    private static func attributeFix(_ attrs: [NSAttributedString.Key: Any], isIcon: Bool, checked: Bool) -> (add: [NSAttributedString.Key: Any], remove: [NSAttributedString.Key])? {
        let target = displayAttributes(
            bold: attrs[boldKey] != nil,
            strikethrough: attrs[strikethroughKey] != nil,
            underline: attrs[underlineKey] != nil,
            colorHex: attrs[colorKey] as? String,
            isTodoIcon: isIcon,
            checked: checked
        )
        var add: [NSAttributedString.Key: Any] = [:]
        var remove: [NSAttributedString.Key] = []
        for key in syncedAttributeKeys {
            if let wanted = target[key] {
                if !attributesEqual(attrs[key], wanted) { add[key] = wanted }
            } else if iconOnlyAttributeKeys.contains(key), attrs[key] != nil {
                remove.append(key)
            }
        }
        return (add.isEmpty && remove.isEmpty) ? nil : (add, remove)
    }

    private static func attributesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left as NSObject, right as NSObject):
            return left.isEqual(right)
        default:
            return false
        }
    }

    // MARK: - 字符工具

    static func isTodoIconUnit(_ unit: unichar) -> Bool {
        unit == uncheckedIconUnit || unit == checkedIconUnit
    }

    private static func isNewline(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }

    private static func isHexDigit(_ unit: unichar) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x46) || (unit >= 0x61 && unit <= 0x66)
    }

    /// `at` 处是否是 `- [ ]` / `- [x]`；是的话连同其后一个可选的空格/制表符一起算进 consumed
    private static func todoMarkerUnits(_ chars: [unichar], at location: Int, limit: Int) -> (checked: Bool, consumed: Int)? {
        guard location + 5 <= limit,
              chars[location] == 0x2D, chars[location + 1] == 0x20, chars[location + 2] == 0x5B, chars[location + 4] == 0x5D,
              chars[location + 3] == 0x20 || chars[location + 3] == 0x78 else { return nil }
        let trailing = location + 5 < limit && (chars[location + 5] == 0x20 || chars[location + 5] == 0x09) ? 1 : 0
        return (chars[location + 3] == 0x78, 5 + trailing)
    }

    // MARK: - 渲染器（递归下降）

    private final class Renderer {
        struct Style: Equatable {
            var bold = false
            var strikethrough = false
            var underline = false
            var colorHex: String? = nil

            func applying(_ marker: Marker) -> Style {
                var style = self
                switch marker {
                case .bold: style.bold = true
                case .strikethrough: style.strikethrough = true
                case .underline: style.underline = true
                case .color(let hex): style.colorHex = hex
                }
                return style
            }
        }

        struct Run {
            var style: Style
            /// 0 = 非图标，1 = 未勾选，2 = 已勾选
            var todo: Int8
            var length: Int
        }

        enum Marker {
            case bold
            case strikethrough
            case underline
            case color(String)

            /// 闭合标记的 UTF-16 长度：`[/c]`、`</u>` 各 4，`**`、`~~` 各 2
            var closeLength: Int {
                switch self {
                case .color, .underline: return 4
                case .bold, .strikethrough: return 2
                }
            }
        }

        enum Token {
            case todo(checked: Bool, consumed: Int)
            case open(Marker, length: Int)
        }

        private let chars: [unichar]
        private let lines: LineIndex
        private var out: [unichar] = []
        private var runs: [Run] = []

        init(chars: [unichar], lines: LineIndex) {
            self.chars = chars
            self.lines = lines
            out.reserveCapacity(chars.count)
        }

        /// 渲染 `[start, end)`：找最早的开始标记 → 在同一段落内找闭合标记 → 递归渲染内部并叠加格式
        func renderRegion(_ start: Int, _ end: Int, style: Style, depth: Int) {
            var literalStart = start
            var cursor = start
            while cursor < end, let (location, token) = nextToken(from: cursor, to: end) {
                if location > literalStart { emit(literalStart..<location, style: style) }
                switch token {
                case .todo(let checked, let consumed):
                    emitIcon(checked: checked, style: style)
                    cursor = location + consumed
                case .open(let marker, let length):
                    let contentStart = location + length
                    let limit = min(end, lines.paragraphEnd(at: location))
                    if depth < StickyNoteMarkdown.maxNestingDepth, let closer = StickyNoteMarkdown.findCloser(marker, in: chars, from: contentStart, to: limit),
                       closer > contentStart {
                        renderRegion(contentStart, closer, style: style.applying(marker), depth: depth + 1)
                        cursor = closer + marker.closeLength
                    } else {
                        // 没闭合、嵌套过深、或内容为空（如一串星号当分隔线）：开始标记按字面输出，从标记之后继续扫
                        emit(location..<contentStart, style: style)
                        cursor = contentStart
                    }
                }
                literalStart = cursor
            }
            if literalStart < end { emit(literalStart..<end, style: style) }
        }

        func build() -> NSAttributedString {
            guard !runs.isEmpty else { return NSAttributedString(string: "") }
            let result = NSMutableAttributedString()
            var offset = 0
            for run in runs {
                let text = String(decoding: out[offset..<offset + run.length], as: UTF16.self)
                let attrs = StickyNoteMarkdown.displayAttributes(
                    bold: run.style.bold, strikethrough: run.style.strikethrough, underline: run.style.underline,
                    colorHex: run.style.colorHex, isTodoIcon: run.todo != 0, checked: run.todo == 2
                )
                result.append(NSAttributedString(string: text, attributes: attrs))
                offset += run.length
            }
            return result
        }

        private func emit(_ range: Range<Int>, style: Style) {
            guard !range.isEmpty else { return }
            out.append(contentsOf: chars[range])
            if let last = runs.last, last.todo == 0, last.style == style {
                runs[runs.count - 1].length += range.count
            } else {
                runs.append(Run(style: style, todo: 0, length: range.count))
            }
        }

        private func emitIcon(checked: Bool, style: Style) {
            out.append(checked ? StickyNoteMarkdown.checkedIconUnit : StickyNoteMarkdown.uncheckedIconUnit)
            runs.append(Run(style: style, todo: checked ? 2 : 1, length: 1))
        }

        /// `[from, to)` 里最早出现的记号（开始标记或待办标记）
        private func nextToken(from: Int, to: Int) -> (location: Int, token: Token)? {
            var index = from
            while index < to {
                switch chars[index] {
                case 0x2A:      // *
                    if index + 1 < to, chars[index + 1] == 0x2A { return (index, .open(.bold, length: 2)) }
                case 0x7E:      // ~
                    if index + 1 < to, chars[index + 1] == 0x7E { return (index, .open(.strikethrough, length: 2)) }
                case 0x3C:      // <
                    if index + 2 < to, chars[index + 1] == 0x75, chars[index + 2] == 0x3E { return (index, .open(.underline, length: 3)) }
                case 0x5B:      // [
                    if let marker = StickyNoteMarkdown.colorStartMarker(in: chars, at: index, limit: to) {
                        return (index, .open(.color(marker.hex), length: marker.length))
                    }
                case 0x2D:      // -
                    if let todo = StickyNoteMarkdown.todoMarkerUnits(chars, at: index, limit: to) {
                        return (index, .todo(checked: todo.checked, consumed: todo.consumed))
                    }
                default:
                    break
                }
                index += 1
            }
            return nil
        }
    }

    /// 从 `from` 起在 `[from, to)` 里找 `marker` 的闭合标记
    private static func findCloser(_ marker: Renderer.Marker, in chars: [unichar], from: Int, to: Int) -> Int? {
        let length = marker.closeLength
        var index = from
        let last = to - length
        while index <= last {
            switch marker {
            case .bold:
                if chars[index] == 0x2A, chars[index + 1] == 0x2A { return index }
            case .strikethrough:
                if chars[index] == 0x7E, chars[index + 1] == 0x7E { return index }
            case .underline:
                if chars[index] == 0x3C, chars[index + 1] == 0x2F, chars[index + 2] == 0x75, chars[index + 3] == 0x3E { return index }
            case .color:
                if chars[index] == 0x5B, chars[index + 1] == 0x2F, chars[index + 2] == 0x63, chars[index + 3] == 0x5D { return index }
            }
            index += 1
        }
        return nil
    }

    // MARK: - 行索引

    /// 把 UTF-16 位置映射到「所在段落的结束位置」。段落 = 连续的非空行；空行 = 空的或只有空格/制表符的行。
    struct LineIndex {
        private let lineStarts: [Int]
        private let paragraphEnds: [Int]

        init(_ chars: [unichar]) {
            var starts: [Int] = [0]
            var blanks: [Bool] = []
            var onlyBlankSoFar = true
            var index = 0
            while index < chars.count {
                let unit = chars[index]
                if StickyNoteMarkdown.isNewline(unit) {
                    blanks.append(onlyBlankSoFar)
                    if unit == 0x0D, index + 1 < chars.count, chars[index + 1] == 0x0A { index += 1 }   // \r\n 算一个换行
                    index += 1
                    starts.append(index)
                    onlyBlankSoFar = true
                } else {
                    if unit != 0x20 && unit != 0x09 { onlyBlankSoFar = false }
                    index += 1
                }
            }
            blanks.append(onlyBlankSoFar)

            var ends = [Int](repeating: 0, count: starts.count)
            let last = starts.count - 1
            ends[last] = blanks[last] ? starts[last] : chars.count
            if last > 0 {
                for line in stride(from: last - 1, through: 0, by: -1) {
                    ends[line] = blanks[line] ? starts[line] : (blanks[line + 1] ? starts[line + 1] : ends[line + 1])
                }
            }
            lineStarts = starts
            paragraphEnds = ends
        }

        /// `position` 所在段落的结束位置（不含）。落在空行上时返回不大于它的值，等于禁止跨空行配对。
        func paragraphEnd(at position: Int) -> Int {
            var low = 0
            var high = lineStarts.count
            while low < high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= position { low = mid + 1 } else { high = mid }
            }
            return paragraphEnds[max(0, low - 1)]
        }
    }

    // MARK: - 序列化用的格式状态

    private enum Format: Int, CaseIterable {
        /// rawValue 越小越靠外：同一落点同时开始的格式按 颜色 > 下划线 > 删除线 > 加粗 嵌套
        case color = 0
        case underline = 1
        case strikethrough = 2
        case bold = 3

        var closeMarker: String {
            switch self {
            case .color: return "[/c]"
            case .underline: return "</u>"
            case .strikethrough: return "~~"
            case .bold: return "**"
            }
        }

        func openMarker(colorHex: String) -> String {
            switch self {
            case .color: return "[c:\(colorHex)]"
            case .underline: return "<u>"
            case .strikethrough: return "~~"
            case .bold: return "**"
            }
        }
    }

    private struct FormatState: Equatable {
        var bold = false
        var strikethrough = false
        var underline = false
        var colorHex: String? = nil

        static let none = FormatState()

        init() {}

        init(_ attrs: [NSAttributedString.Key: Any]) {
            bold = attrs[StickyNoteMarkdown.boldKey] != nil
            strikethrough = attrs[StickyNoteMarkdown.strikethroughKey] != nil
            underline = attrs[StickyNoteMarkdown.underlineKey] != nil
            colorHex = attrs[StickyNoteMarkdown.colorKey] as? String
        }

        func has(_ format: Format) -> Bool {
            switch format {
            case .bold: return bold
            case .strikethrough: return strikethrough
            case .underline: return underline
            case .color: return colorHex != nil
            }
        }
    }
}
