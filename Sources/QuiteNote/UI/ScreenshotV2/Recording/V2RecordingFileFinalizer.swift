import Foundation

/// 录屏文件落盘：临时文件 → 目标目录 + 系统风格命名 + 重名去重
///
/// 与 ScreenshotService.exportImageFile 的命名/去重约定保持一致
/// （前缀换成「录屏」、扩展名 .mp4），用户感知两套保存行为是同一套规则。
/// 先写临时文件、成功后再移动——中途取消/崩溃不会在目标目录留下半个坏文件。
enum V2RecordingFileFinalizer {

    /// 解析保存目录：设置项优先，未设置默认「下载」（与截图一致）
    static func defaultDirectory() -> URL {
        let pref = PreferencesManager.shared.screenshotSaveDirectory
        if !pref.isEmpty {
            return URL(fileURLWithPath: (pref as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    /// 把录制完成的临时文件移动到目标目录，重名自动加 -2 后缀
    /// - Returns: 最终文件的绝对 URL
    static func finalize(tempURL: URL,
                         directory: URL,
                         date: Date = Date(),
                         fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = "录屏 \(formatter.string(from: date))"

        var fileURL = directory.appendingPathComponent("\(baseName).mp4")
        var counter = 2
        while fileManager.fileExists(atPath: fileURL.path) {
            fileURL = directory.appendingPathComponent("\(baseName)-\(counter).mp4")
            counter += 1
        }

        try fileManager.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }
}
