import SwiftUI

/// 重构验证测试运行入口
/// 在 MainApp.swift 或调试入口调用此方法
struct RunRefactoringTests {

    /// 运行所有重构验证测试
    @MainActor
    static func runAll() {
        RefactoringTestCases.runAllTests()
    }
}
