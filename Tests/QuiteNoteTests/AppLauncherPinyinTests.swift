import XCTest
@testable import QuiteNote

/// 拼音转换（CFStringTransform 原生实现）的确定性用例
final class AppLauncherPinyinTests: XCTestCase {

    func test纯中文_微信() {
        let r = PinyinTransformer.transliterate("微信")
        XCTAssertEqual(r.full, "wei xin")
        XCTAssertEqual(r.initials, "wx")
    }

    func test纯中文_多音字按单字读音() {
        // "乐" 无上下文时读 le（音乐语境应为 yuè）——首字母 "wyy" 仍能前缀命中 "wyyyl"
        let r = PinyinTransformer.transliterate("网易云音乐")
        XCTAssertEqual(r.full, "wang yi yun yin le")
        XCTAssertEqual(r.initials, "wyyyl")
        XCTAssertTrue(r.initials.hasPrefix("wyy"))
    }

    func test纯英文_只取单词首字母() {
        let r = PinyinTransformer.transliterate("Google Chrome")
        XCTAssertEqual(r.full, "google chrome")
        XCTAssertEqual(r.initials, "gc")
    }

    func test中英混排_QQ音乐() {
        let r = PinyinTransformer.transliterate("QQ音乐")
        XCTAssertEqual(r.full, "qq yin le")
        XCTAssertEqual(r.initials, "qyl")
    }

    func testü转v_键盘输入习惯() {
        XCTAssertEqual(PinyinTransformer.transliterate("绿").full, "lv")
        XCTAssertEqual(PinyinTransformer.transliterate("女").full, "nv")
    }

    func test带caron声调元音不被ü替换误伤() {
        // 回归钉死：NSString.replacingOccurrences 的宽松匹配曾让 ǚ(U+01DA) 吃掉
        // "suǒ" 里的 u+ǒ，"锁屏"被毁成 "svping"；标量级替换后必须正确
        XCTAssertEqual(PinyinTransformer.transliterate("锁屏").full, "suo ping")
        XCTAssertEqual(PinyinTransformer.transliterate("锁屏").initials, "sp")
        XCTAssertEqual(PinyinTransformer.transliterate("屏幕").full, "ping mu")
    }

    func test空字符串() {
        let r = PinyinTransformer.transliterate("")
        XCTAssertEqual(r.full, "")
        XCTAssertEqual(r.initials, "")
    }

    func testCJK判定() {
        XCTAssertTrue(PinyinTransformer.isCJK("微".unicodeScalars.first!))
        XCTAssertTrue(PinyinTransformer.isCJK("㐀".unicodeScalars.first!)) // 扩展 A 起点 U+3400
        XCTAssertFalse(PinyinTransformer.isCJK("a".unicodeScalars.first!))
        XCTAssertFalse(PinyinTransformer.isCJK("，".unicodeScalars.first!)) // 中文标点不算
    }
}
