import Carbon
import Foundation

/// 面板唤起期间的输入源切换（Alfred/Raycast 式 "force English"）
///
/// 启动器的主匹配面是缩略词/全拼（wx → 微信、weixin → 微信），英文键盘直达；
/// 中文 IME 下打 "wx" 会被组词吞掉上屏汉字，搜索反而失效。面板唤起时记住当前
/// 输入源、切到系统 ASCII 键盘，收起时还原——用户回到原应用继续打中文，
/// 不能被丢在英文键盘上。
///
/// 剪贴板面板刻意不接此能力：那边高频用中文搜内容，强切是体验回退。
enum InputSourceSwitcher {

    private static var previousSource: TISInputSource?

    /// 面板唤起：记住当前输入源并切到英文键盘。已是 ASCII 键盘时不动（也不记录）。
    /// 可重入：切换会话中重复调用是幂等的（面板互斥/快速开关场景）。
    @discardableResult
    static func selectEnglishForPanel() -> Bool {
        guard previousSource == nil else { return true }
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            DiagnosticCenter.warning("Launcher", "切英文输入失败：读不到当前输入源")
            return false
        }
        guard !isASCIICapable(current) else { return false }
        guard let target = englishSource() else {
            DiagnosticCenter.warning("Launcher", "切英文输入失败：无启用的 ASCII 键盘")
            return false
        }
        guard TISSelectInputSource(target) == noErr else {
            // macOS 26 后台 app 的切换请求会被静默拒绝——调用方须在面板成为 key 后重试
            DiagnosticCenter.warning("Launcher", "切英文输入被系统拒绝（app 未前台？）")
            return false
        }
        previousSource = current
        DiagnosticCenter.info("Launcher", "已切英文键盘（面板会话），收起时还原")
        return true
    }

    /// 面板收起：还原唤起前的输入源
    static func restore() {
        guard let previous = previousSource else { return }
        previousSource = nil
        TISSelectInputSource(previous)
    }

    /// 从启用的 ASCII 键盘里选英文源：ABC > US > 首个可用
    static func englishSource() -> TISInputSource? {
        let filters = [
            kTISPropertyInputSourceIsEnabled as String: kCFBooleanTrue as Any,
            kTISPropertyInputSourceIsASCIICapable as String: kCFBooleanTrue as Any,
        ] as CFDictionary
        guard let cfList = TISCreateInputSourceList(filters, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        let ids = cfList.map { sourceID($0) }
        guard !ids.isEmpty else { return nil }
        let preferredOrder = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        for preferred in preferredOrder {
            if let index = ids.firstIndex(of: preferred) {
                return cfList[index]
            }
        }
        return cfList[0]
    }

    private static func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else {
            return false
        }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }

    private static func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
