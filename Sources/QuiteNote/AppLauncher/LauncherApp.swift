import Foundation

/// 应用启动器目录里的一个应用条目（值类型，图标由 AppCatalogStore 单独缓存）
///
/// 搜索热路径要快，规范化字段（小写/去变音符/拼音去空格）在**构造时一次性预计算**，
/// 按键搜索只做 hasPrefix/contains——此前每次按键对全目录重复 fold 是卡顿主因。
/// Codable：预计算字段一并编解码，磁盘缓存恢复零重算（跳过 CFStringTransform）。
struct LauncherApp: Identifiable, Equatable, Codable {
    let name: String
    let bundleID: String
    let url: URL
    /// 是否系统自带（/System 下的应用，列表里打「系统」徽标）
    let isSystem: Bool
    let pinyinFull: String
    let pinyinInitials: String

    // MARK: - 预计算搜索字段（构造时算好，搜索零转换成本）

    /// 名称：小写 + 去变音符
    let nameNormalized: String
    /// 全拼：小写、去空格（"wei xin" → "weixin"）
    let pinyinCompact: String
    /// 首字母缩写：小写
    let initialsNormalized: String
    /// bundleID：小写
    let bundleIDLower: String

    /// 唯一键：优先 bundleID，取不到时退回路径（App Store 外散装 app 可能无 bundleID）
    var id: String { bundleID.isEmpty ? url.path : bundleID }

    init(name: String, bundleID: String, url: URL, isSystem: Bool) {
        let pinyin = PinyinTransformer.transliterate(name)
        self.init(name: name, bundleID: bundleID, url: url, isSystem: isSystem,
                  pinyinFull: pinyin.full, pinyinInitials: pinyin.initials)
    }

    init(name: String, bundleID: String, url: URL, isSystem: Bool,
         pinyinFull: String, pinyinInitials: String) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
        self.isSystem = isSystem
        self.pinyinFull = pinyinFull
        self.pinyinInitials = pinyinInitials

        let folded: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        self.nameNormalized = folded(name)
        self.pinyinCompact = folded(pinyinFull).replacingOccurrences(of: " ", with: "")
        self.initialsNormalized = folded(pinyinInitials)
        self.bundleIDLower = bundleID.lowercased()
    }
}
