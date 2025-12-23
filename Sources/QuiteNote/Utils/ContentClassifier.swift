import Foundation

/// 针对输入内容进行快速规则判断，识别 URL、密钥、代码、文档等类型
struct ContentClassifier {
    
    /// 识别内容类型并返回对应的标签
    /// - Parameter content: 输入的文本内容
    /// - Returns: 识别出的标签数组
    static func classify(_ content: String) -> [String] {
        var tags: [String] = []
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. URL 判断
        if isURL(trimmed) {
            tags.append("URL")
        }
        
        // 2. 密钥/Token 判断
        if isSecret(trimmed) {
            tags.append("密钥")
        }
        
        // 3. 代码判断
        if isCode(trimmed) {
            tags.append("代码")
        }
        
        // 4. 文档判断
        if isDocumentation(trimmed) {
            tags.append("文档")
        }
        
        return tags
    }
    
    /// 判断是否为 URL
    private static func isURL(_ content: String) -> Bool {
        let pattern = "^(http|https)://[\\w\\-_]+(\\.[\\w\\-_]+)+([\\w\\-\\.,@?^=%&:/~\\+#]*[\\w\\-\\@?^=%&/~\\+#])?$"
        return content.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// 判断是否为密钥/Token
    private static func isSecret(_ content: String) -> Bool {
        // 常见的密钥模式：
        let patterns = [
            "sk-[a-zA-Z0-9]{32,}", // OpenAI etc
            "ghp_[a-zA-Z0-9]{30,}", // GitHub
            "^[a-fA-F0-9]{32,64}$", // Hex keys
            "(?i)api[-_]?key",      // Contains api-key
            "(?i)secret[-_]?key",   // Contains secret-key
            "(?i)access[-_]?token", // Contains access-token
            "(?i)auth[-_]?token",   // Contains auth-token
            "(?i)password",         // Contains password
            "(?i)private[-_]?key"   // Contains private-key
        ]
        
        for pattern in patterns {
            if content.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// 判断是否为代码
    private static func isCode(_ content: String) -> Bool {
        let codeKeywords = [
            "func ", "class ", "struct ", "import ", "var ", "let ",
            "function ", "const ", "export ", "public ", "private ",
            "void ", "int ", "String ", "boolean ", "override ",
            "if (", "while (", "for (", "return ", "try {", "catch ("
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var matchCount = 0
        
        for line in lines.prefix(20) { // 只检查前20行
            for keyword in codeKeywords {
                if line.contains(keyword) {
                    matchCount += 1
                    break
                }
            }
        }
        
        // 如果包含大括号且有关键字，或者关键字较多，认为是代码
        let hasBraces = content.contains("{") && content.contains("}")
        return (hasBraces && matchCount >= 1) || matchCount >= 3
    }
    
    /// 判断是否为产品文档/文章
    private static func isDocumentation(_ content: String) -> Bool {
        let docKeywords = [
            "Introduction", "Getting Started", "Usage", "API Reference",
            "Configuration", "Installation", "Example", "Overview",
            "核心功能", "快速开始", "安装指南", "使用说明", "参数详解"
        ]
        
        var matchCount = 0
        for keyword in docKeywords {
            if content.contains(keyword) {
                matchCount += 1
            }
        }
        
        // 篇幅较长且包含标题类关键字
        return content.count > 300 && matchCount >= 2
    }
}
