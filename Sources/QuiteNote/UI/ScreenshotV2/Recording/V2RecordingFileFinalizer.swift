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
            let bookmarkStore = SecurityScopedBookmarkStore.shared
            if let scopedURL = bookmarkStore.resolve(forKey: "screenshotSaveDirectoryBookmark") {
                return scopedURL
            }
            if !bookmarkStore.hasBookmark(forKey: "screenshotSaveDirectoryBookmark") {
                return URL(fileURLWithPath: (pref as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    /// 把剪辑导出的临时文件移动到原片旁边，不覆盖原始录屏。
    /// 重名时追加 -2、-3，保证每次导出都是可恢复的独立文件。
    /// 反复剪辑不叠后缀：先剥掉已有的「 - 剪辑版」再统一追加一个。
    static func finalizeEdited(tempURL: URL,
                               beside sourceURL: URL,
                               fileManager: FileManager = .default) throws -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var sourceBase = sourceURL.deletingPathExtension().lastPathComponent
        while let range = sourceBase.range(of: " - 剪辑版", options: .backwards) {
            sourceBase = String(sourceBase[sourceBase.startIndex..<range.lowerBound])
        }
        let baseName = "\(sourceBase) - 剪辑版"
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
