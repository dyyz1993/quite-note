import XCTest
@testable import QuiteNote

final class AppLocalizationTests: XCTestCase {
    func testChineseSystemLanguageResolvesToSimplifiedChinese() {
        XCTAssertEqual(AppLocalization.resolvedLanguage(preferredLanguages: ["zh-CN", "en-US"]), "zh-Hans")
    }

    func testEnglishSystemLanguageResolvesToEnglish() {
        XCTAssertEqual(AppLocalization.resolvedLanguage(preferredLanguages: ["en-GB", "zh-Hans"]), "en")
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLocalization.resolvedLanguage(preferredLanguages: ["zh-TW", "fr-FR"]), "en")
    }
}
