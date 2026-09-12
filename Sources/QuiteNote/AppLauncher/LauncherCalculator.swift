import Foundation

/// 启动器内置计算器（Alfred 式快速算术）：输入 "12+34"、"(50-8)×2"、"2^10"、"√144" 即时出结果
///
/// 递归下降解析器，支持 + - * / %、幂（^ 或 **，右结合）、√、上标 ²³、
/// 常量 e/π、括号、一元正负、小数；全角运算符（＋－×÷（））先归一为 ASCII。
/// 纯函数零依赖，除零/溢出/残缺表达式返回 nil。
enum LauncherCalculator {

    /// 全角/中文习惯符号归一 + 去空白
    static func normalizeExpression(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "％", with: "%")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
    }

    /// 输入"像算式"吗：至少一个数字（或常量）且至少一个运算符（"1" 不算，"1+" 算——
    /// 输入中途即切计算模式，残缺表达式求值失败只是不显示结果卡）
    static func looksLikeExpression(_ text: String) -> Bool {
        let s = normalizeExpression(text)
        guard s.contains(where: { $0.isNumber }) || s.contains("π") else { return false }
        return s.contains(where: { "+-*/%^√".contains($0) })
            || s.contains("**")
            || s.contains("²") || s.contains("³")
    }

    /// 求值；非法/除零/溢出返回 nil
    static func evaluate(_ raw: String) -> Double? {
        var s = normalizeExpression(raw)
        // 上标数字 → ^ 形式（"x²" → "x^2"）
        for (sup, digit) in [("⁰", "0"), ("¹", "1"), ("²", "2"), ("³", "3"),
                             ("⁴", "4"), ("⁵", "5"), ("⁶", "6"), ("⁷", "7"),
                             ("⁸", "8"), ("⁹", "9")] {
            s = s.replacingOccurrences(of: sup, with: "^\(digit)")
        }
        // "**" 归一为 "^"（保留 ^ 优先级右结合语义）
        s = s.replacingOccurrences(of: "**", with: "^")

        let chars = Array(s)
        guard !chars.isEmpty,
              chars.allSatisfy({ $0.isNumber || "+-*/%^().".contains($0) || "√πe".contains($0) }) else { return nil }
        var parser = Parser(tokens: chars)
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        return value.isFinite ? value : nil
    }

    /// 结果展示：整数去小数点，小数去尾零（最多 10 位有效）
    static func formatResult(_ value: Double) -> String {
        if value == value.rounded(),
           abs(value) < 1e15,
           let asInt = Int64(exactly: value) {
            return String(asInt)
        }
        return String(format: "%.10g", value)
    }

    // MARK: - 递归下降解析
    //
    // expression := term (('+' | '-') term)*
    // term       := unary (('*' | '/' | '%') unary)*
    // unary      := ('+' | '-')? unary | power
    // power      := primary ('^' unary)?          （右结合：2^3^2 = 2^(3^2) = 512）
    // primary    := number | 'e' | 'π' | '√' power | '(' expression ')'
    //
    // 幂优先级高于一元负号（-2^2 = -(2^2) = -4，数学惯例），底数取 primary

    private struct Parser {
        let tokens: [Character]
        var index = 0

        var isAtEnd: Bool { index >= tokens.count }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                switch op {
                case "+": value += rhs
                case "-": value -= rhs
                default: return nil
                }
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                index += 1
                guard let rhs = parseUnary() else { return nil }
                switch op {
                case "*": value *= rhs
                case "/": value /= rhs
                case "%": value = value.truncatingRemainder(dividingBy: rhs)
                default: return nil
                }
            }
            return value
        }

        mutating func parseUnary() -> Double? {
            if let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return op == "-" ? -value : value
            }
            return parsePower()
        }

        /// 幂：右结合（2^3^2 = 512）；指数侧递归回 unary 以支持 2^-3、2^√9
        mutating func parsePower() -> Double? {
            guard let base = parsePrimary() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exponent = parseUnary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func parsePrimary() -> Double? {
            if peek() == "(" {
                index += 1
                guard let value = parseExpression(), peek() == ")" else { return nil }
                index += 1
                return value
            }
            // √ 前缀：√144、√(2+7)、√9^2（√ 只作用于紧随的 power）
            if peek() == "√" {
                index += 1
                guard let value = parsePower() else { return nil }
                guard value >= 0 else { return nil }
                return value.squareRoot()
            }
            // 常量 e / π（前面带数字视为非法，"2e" 歧义拒绝）
            if let c = peek(), c == "e" || c == "π" {
                index += 1
                return c == "e" ? M_E : .pi
            }
            // 数字（含小数点；小数点必须后跟数字，"1." 宽容解析）
            let start = index
            while let c = peek(), c.isNumber || c == "." {
                index += 1
            }
            guard index > start,
                  tokens[start] != ".",
                  let value = Double(String(tokens[start..<index])) else { return nil }
            return value
        }

        private func peek() -> Character? {
            index < tokens.count ? tokens[index] : nil
        }
    }
}
