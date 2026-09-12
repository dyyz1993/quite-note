import AppKit
import Foundation

/// 截图、录屏和快剪成片共用的用户可见导出目录。
///
/// App Sandbox 中 `.downloadsDirectory` 会解析到容器目录，不能把它伪装成用户的
/// 「下载」文件夹。所有对外导出必须来自用户通过系统目录选择器明确授权的目录。
enum UserExportDirectory {
    static let bookmarkKey = "screenshotSaveDirectoryBookmark"

    enum ResolutionError: LocalizedError, Equatable {
        case noDirectorySelected
        case authorizationUnavailable

        var errorDescription: String? {
            switch self {
            case .noDirectorySelected:
                return "请先选择导出目录"
            case .authorizationUnavailable:
                return "导出目录的访问授权已失效，请重新选择目录"
            }
        }
    }

    /// 仅返回已由用户选择并且当前仍可访问的目录；绝不退回到应用沙盒目录。
    static func configuredDirectory() -> Result<URL, ResolutionError> {
        let preferences = PreferencesManager.shared
        guard !preferences.screenshotSaveDirectory.isEmpty else {
            return .failure(.noDirectorySelected)
        }

        guard SecurityScopedBookmarkStore.shared.hasBookmark(forKey: bookmarkKey),
              let url = SecurityScopedBookmarkStore.shared.resolve(forKey: bookmarkKey) else {
            return .failure(.authorizationUnavailable)
        }
        return .success(url)
    }

    /// 获取目录；首次导出或原授权失效时，明确要求用户选择一个目录。
    /// 调用方必须来自用户触发的保存/导出操作。
    static func resolveForUserInitiatedExport() -> Result<URL, ResolutionError> {
        switch configuredDirectory() {
        case .success(let url):
            return .success(url)
        case .failure(let reason):
            return requestDirectory(replacing: reason)
        }
    }

    private static func requestDirectory(replacing reason: ResolutionError) -> Result<URL, ResolutionError> {
        // NSOpenPanel 只能在主线程显示。后台调用直接失败，避免阻塞或悄悄写入容器。
        guard Thread.isMainThread else {
            DiagnosticCenter.warning("Save", "导出目录未在主线程请求，已取消导出")
            return .failure(reason)
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择此文件夹"
        panel.message = reason == .authorizationUnavailable
            ? "导出目录授权已失效。请重新选择截图、录屏和快剪的保存目录（后续导出将始终保存到这里）。"
            : "请选择截图、录屏和快剪导出的保存目录（后续导出将始终保存到这里）。"

        guard panel.runModal() == .OK, let url = panel.url,
              PreferencesManager.shared.setScreenshotSaveDirectory(url) else {
            return .failure(reason)
        }
        return configuredDirectory()
    }
}
