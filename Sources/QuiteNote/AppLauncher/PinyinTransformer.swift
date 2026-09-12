import Foundation

/// 中文 → 拼音转换（应用启动器搜索用）
///
/// 用 CoreFoundation 原生 `CFStringTransform` 实现，零第三方依赖：
/// kCFStringTransformMandarinLatin 把中文转成带声调拼音（"微信" → "wēi xìn"），
/// 再用 kCFStringTransformStripCombiningMarks 去声调（→ "wei xin"）。
///
/// 已知局限（多音字）：逐字符无上下文转换，"乐" 永远出 "le"（音乐语境应为 yuè）、
/// "长" 出 "chang"——对搜索匹配可接受（首字母/前缀命中仍有效，如 "wyy" 仍能前缀命中
/// "wyyyl"），不追求读音正确。
enum PinyinTransformer {

    struct Result: Equatable {
        /// 全拼（小写，音节间空格分隔，拉丁部分保留原词），如 "微信" → "wei xin"、"Google Chrome" → "google chrome"
        let full: String
        /// 首字母缩写（每个音节/英文单词取首字母），如 "微信" → "wx"、"Google Chrome" → "gc"
        let initials: String
    }

    static func transliterate(_ text: String) -> Result {
        var fullParts: [String] = []
        var initialParts: [String] = []
        var cjkRun = ""
        var latinRun = ""

        // 把累积的中文段转拼音并落袋
        func flushCJK() {
            guard !cjkRun.isEmpty else { return }
            let syllables = pinyinSyllables(of: cjkRun)
            fullParts.append(syllables.joined(separator: " "))
            initialParts.append(syllables.map { String($0.prefix(1)) }.joined())
            cjkRun = ""
        }

        // 拉丁字母/数字按词累积（"Google" 是一个词，不是 g o o g l e）
        func flushLatin() {
            guard !latinRun.isEmpty else { return }
            fullParts.append(latinRun)
            initialParts.append(String(latinRun.prefix(1)))
            latinRun = ""
        }

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                flushLatin()
                cjkRun.unicodeScalars.append(scalar)
            } else {
                flushCJK()
                let isAlnum = Character(scalar).isLetter || Character(scalar).isNumber
                if isAlnum {
                    // 英文单词首字母参与缩写（"Google Chrome" → gc；"VSCode" 只取 v）
                    latinRun += Character(scalar).description.lowercased()
                } else {
                    flushLatin()
                }
            }
        }
        flushCJK()
        flushLatin()

        return Result(full: fullParts.joined(separator: " "), initials: initialParts.joined())
    }

    /// 中文段 → 拼音音节数组；转换失败时回退整段原样（保证搜索仍有名称可匹配）
    static func pinyinSyllables(of cjkText: String) -> [String] {
        let mutable = NSMutableString(string: cjkText)
        guard CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false) else {
            return [cjkText]
        }
        // ü → v 必须在去声调之前做：StripCombiningMarks 会把 ü 直接拆成 u（绿会变 lu，
        // 而键盘输入习惯是 lv）。⚠️ 必须按标量精确替换——NSString.replacingOccurrences
        // 的检索对组合变音符做宽松匹配（U+01DA ǚ 能匹配 "u"+ǒ，"锁屏"曾被毁成 svping）
        let withV = Self.umlautToV(mutable as String)
        let stripped = NSMutableString(string: withV)
        guard CFStringTransform(stripped, nil, kCFStringTransformStripCombiningMarks, false) else {
            return withV.split(whereSeparator: { $0 == " " }).map { $0.lowercased() }
        }
        let syllables = (stripped as String)
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .map { $0.lowercased() }
        return syllables.isEmpty ? [cjkText] : syllables
    }

    /// ü → v 的标量级精确替换：五种预组形式 + 分解形式（u + 组合分音符 U+0308）。
    /// 只动 ü，其他带调元音（ǎ ě ǐ ǒ ǔ…）原样保留给去声调步骤处理。
    static func umlautToV(_ s: String) -> String {
        let tonedU: Set<Unicode.Scalar> = ["\u{01D6}", "\u{01D8}", "\u{01DA}", "\u{01DC}", "\u{00FC}"]
        let input = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < input.count {
            let c = input[i]
            if tonedU.contains(c) {
                out.append("v")
                i += 1
            } else if c == "u", i + 1 < input.count, input[i + 1] == "\u{0308}" {
                // 分解形式的 u+分音符（其后可能跟声调组合标记，留给去声调步骤）
                out.append("v")
                i += 2
            } else {
                out.append(c)
                i += 1
            }
        }
        return String(out)
    }

    /// CJK 统一表意文字（含扩展 A / 兼容区），不含标点
    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}
