import Foundation

/// 「导出所有记录为 Markdown」的落盘与提示。三个入口（状态栏菜单、⌥⌘E、设置 → 记录）
/// 共用：失败统一弹错误提示，成功后由调用方按各自的入口提示
@MainActor
enum RecordMarkdownExport {
    static func write(
        _ result: Result<String, Error>,
        to url: URL,
        store: RecordStore,
        onSuccess: @escaping (URL) -> Void
    ) {
        switch result {
        case .failure(let error):
            store.postToast("导出失败：\(error.localizedDescription)", type: "error")
        case .success(let markdown):
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                onSuccess(url)
            } catch {
                store.postToast("导出失败：\(error.localizedDescription)", type: "error")
            }
        }
    }
}
