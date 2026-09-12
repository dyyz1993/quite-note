import XCTest
@testable import QuiteNote

/// 启动器内置计算器（递归下降求值器）
final class LauncherCalculatorTests: XCTestCase {

    // MARK: - 基础运算与优先级

    func test加减乘除() {
        XCTAssertEqual(LauncherCalculator.evaluate("12+34"), 46)
        XCTAssertEqual(LauncherCalculator.evaluate("50-8"), 42)
        XCTAssertEqual(LauncherCalculator.evaluate("6*7"), 42)
        XCTAssertEqual(LauncherCalculator.evaluate("10/4"), 2.5)
        XCTAssertEqual(LauncherCalculator.evaluate("10%3"), 1)
    }

    func test运算符优先级() {
        XCTAssertEqual(LauncherCalculator.evaluate("2+3*4"), 14)
        XCTAssertEqual(LauncherCalculator.evaluate("2*3+4"), 10)
        XCTAssertEqual(LauncherCalculator.evaluate("100-20/4"), 95)
    }

    func test括号改变优先级() {
        XCTAssertEqual(LauncherCalculator.evaluate("(2+3)*4"), 20)
        XCTAssertEqual(LauncherCalculator.evaluate("(50-8)*2"), 84)
        XCTAssertEqual(LauncherCalculator.evaluate("((1+2)*(3+4))"), 21)
    }

    func test一元正负与连续运算() {
        XCTAssertEqual(LauncherCalculator.evaluate("-5+3"), -2)
        XCTAssertEqual(LauncherCalculator.evaluate("2*-3"), -6)
        XCTAssertEqual(LauncherCalculator.evaluate("-(2+3)"), -5)
        XCTAssertEqual(LauncherCalculator.evaluate("1+2+3+4"), 10)
    }

    func test小数() {
        XCTAssertEqual(LauncherCalculator.evaluate("0.5*8"), 4)
        XCTAssertEqual(LauncherCalculator.evaluate("1.5+2.25"), 3.75)
        XCTAssertEqual(LauncherCalculator.evaluate("12.5/2.5"), 5)
    }

    // MARK: - 幂与高级数学（第二轮扩展）

    func test幂运算() {
        XCTAssertEqual(LauncherCalculator.evaluate("2^10"), 1024)
        XCTAssertEqual(LauncherCalculator.evaluate("5^3"), 125)
        XCTAssertEqual(LauncherCalculator.evaluate("2**10"), 1024)   // 双星号等价
        XCTAssertEqual(LauncherCalculator.evaluate("9^0.5") ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(LauncherCalculator.evaluate("2^-3"), 0.125)   // 负指数
    }

    func test幂右结合() {
        XCTAssertEqual(LauncherCalculator.evaluate("2^3^2"), 512)    // 2^(3^2) 非 (2^3)^2
        XCTAssertEqual(LauncherCalculator.evaluate("2^2^3"), 256)
    }

    func test幂优先级高于乘除与负号() {
        XCTAssertEqual(LauncherCalculator.evaluate("-2^2"), -4)      // 数学惯例：-(2^2)
        XCTAssertEqual(LauncherCalculator.evaluate("2^2*3"), 12)
        XCTAssertEqual(LauncherCalculator.evaluate("10/2^2"), 2.5)
        XCTAssertEqual(LauncherCalculator.evaluate("(2+3)^2"), 25)   // 括号底数
    }

    func test平方根() {
        XCTAssertEqual(LauncherCalculator.evaluate("√144"), 12)
        XCTAssertEqual(LauncherCalculator.evaluate("√(7+2)"), 3)
        XCTAssertEqual(LauncherCalculator.evaluate("√2") ?? 0, 2.squareRoot(), accuracy: 1e-12)
        XCTAssertNil(LauncherCalculator.evaluate("√-4"))             // 负数开方
    }

    func test上标平方立方() {
        XCTAssertEqual(LauncherCalculator.evaluate("5²"), 25)
        XCTAssertEqual(LauncherCalculator.evaluate("2³"), 8)
        XCTAssertEqual(LauncherCalculator.evaluate("3²+4²"), 25)     // 勾股数
        XCTAssertEqual(LauncherCalculator.evaluate("(1+2)²"), 9)
        XCTAssertEqual(LauncherCalculator.evaluate("2⁵"), 32)        // 其他上标数字
    }

    func test常量e和π() {
        XCTAssertEqual(LauncherCalculator.evaluate("π*2") ?? 0, 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(LauncherCalculator.evaluate("e^2") ?? 0, M_E * M_E, accuracy: 1e-12)
        XCTAssertEqual(LauncherCalculator.evaluate("π") ?? 0, .pi, accuracy: 1e-12)
        XCTAssertNil(LauncherCalculator.evaluate("2e"))              // 歧义拒绝
    }

    func test混合高级表达式() {
        XCTAssertEqual(LauncherCalculator.evaluate("√(3²+4²)"), 5)   // √(9+16) = 5
        XCTAssertEqual(LauncherCalculator.evaluate("2^√9"), 8)       // 2^3
        XCTAssertEqual(LauncherCalculator.evaluate("π*5²") ?? 0, 25 * .pi, accuracy: 1e-12)
    }

    // MARK: - 全角符号归一（中文输入法习惯）

    func test全角运算符() {
        XCTAssertEqual(LauncherCalculator.evaluate("12＋34"), 46)
        XCTAssertEqual(LauncherCalculator.evaluate("（50－8）×2"), 84)
        XCTAssertEqual(LauncherCalculator.evaluate("10÷4"), 2.5)
        XCTAssertEqual(LauncherCalculator.evaluate("1 ＋ 1"), 2)
    }

    // MARK: - 非法输入

    func test残缺与非法表达式返回nil() {
        XCTAssertNil(LauncherCalculator.evaluate("12+"))
        XCTAssertNil(LauncherCalculator.evaluate("(1+2"))
        XCTAssertNil(LauncherCalculator.evaluate("1+2)"))
        XCTAssertNil(LauncherCalculator.evaluate("1/0"))       // 除零 → inf → nil
        XCTAssertNil(LauncherCalculator.evaluate("10%0"))      // 模零 → nan → nil
        XCTAssertNil(LauncherCalculator.evaluate("1..2"))      // 非法数字
        // "1." 是 "1.5" 的输入中间态，宽容解析为 1（Double("1.") == 1.0）
        XCTAssertEqual(LauncherCalculator.evaluate("1."), 1)
        XCTAssertNil(LauncherCalculator.evaluate("abc"))
        XCTAssertNil(LauncherCalculator.evaluate(""))
        XCTAssertNil(LauncherCalculator.evaluate("wx"))        // 应用名不是算式
        XCTAssertNil(LauncherCalculator.evaluate("1a+2"))      // 混入字母
    }

    // MARK: - 算式识别

    func testLooksLikeExpression() {
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("12+34"))
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("1+"))        // 输入中途即切计算模式
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("(50-8)×2"))
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("-3*2"))
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("2^"))         // 幂中途
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("5²"))         // 上标
        XCTAssertTrue(LauncherCalculator.looksLikeExpression("π*2"))
        XCTAssertFalse(LauncherCalculator.looksLikeExpression("1"))        // 纯数字仍是应用搜索
        XCTAssertFalse(LauncherCalculator.looksLikeExpression("wx"))
        XCTAssertFalse(LauncherCalculator.looksLikeExpression("+"))        // 无数字
        XCTAssertFalse(LauncherCalculator.looksLikeExpression("√"))        // 无数字
    }

    // MARK: - 结果格式化

    func testFormatResult() {
        XCTAssertEqual(LauncherCalculator.formatResult(46.0), "46")
        XCTAssertEqual(LauncherCalculator.formatResult(2.5), "2.5")
        XCTAssertEqual(LauncherCalculator.formatResult(-84), "-84")
        XCTAssertEqual(LauncherCalculator.formatResult(1.0 / 3), "0.3333333333")
        XCTAssertEqual(LauncherCalculator.formatResult(1000000), "1000000")
    }
}
