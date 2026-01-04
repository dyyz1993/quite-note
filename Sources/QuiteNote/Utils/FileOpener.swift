import AppKit

/// 文件打开器：根据偏好设置选择合适的应用程序打开文件
struct FileOpener {
    /// 支持的编辑器枚举
    enum Editor: String, CaseIterable {
        case system = "System Default"
        case vscode = "Visual Studio Code"
        case cursor = "Cursor"
        case textedit = "TextEdit"
        case sublime = "Sublime Text"
        case xcode = "Xcode"
        
        /// 对应的 Bundle Identifier
        var bundleId: String? {
            switch self {
            case .system: return nil
            case .vscode: return "com.microsoft.VSCode"
            case .cursor: return "com.todesktop.230313mzl4w4u92"
            case .textedit: return "com.apple.TextEdit"
            case .sublime: return "com.sublimetext.4"
            case .xcode: return "com.apple.dt.Xcode"
            }
        }
    }
    
    /// 使用指定的编辑器打开文件
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - preferredEditor: 偏好设置中的编辑器名称
    static func open(url: URL, preferredEditor: String) {
        // 1. 判断是否是图片类型
        let isImage: Bool
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            isImage = type.conforms(to: .image)
        } else {
            // 后备方案：通过后缀判断
            let ext = url.pathExtension.lowercased()
            isImage = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic"].contains(ext)
        }

        // 2. 如果是图片，直接用系统默认（通常是预览应用），不走编辑器
        if isImage {
            NSWorkspace.shared.open(url)
            return
        }

        // 3. 非图片类型，继续走原有的编辑器逻辑
        let editor = Editor(rawValue: preferredEditor)
        
        var appUrl: URL? = nil
        
        if let editor = editor {
            // 处理预设编辑器
            if let bundleId = editor.bundleId {
                appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            }
        } else {
            // 处理自定义路径
            let customUrl = URL(fileURLWithPath: preferredEditor)
            if FileManager.default.fileExists(atPath: customUrl.path) {
                appUrl = customUrl
            }
        }
        
        // 如果找到了应用 URL，尝试打开
        if let finalAppUrl = appUrl {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: finalAppUrl, configuration: configuration) { _, error in
                if let error = error {
                    print("[DEBUG] Failed to open with \(preferredEditor): \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else {
            // 否则使用系统默认
            NSWorkspace.shared.open(url)
        }
    }
}
