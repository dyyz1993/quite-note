import Foundation
import AppKit

/// 贴纸页面数据模型
struct StickyNotePage: Codable, Identifiable {
    var id = UUID()
    var content: String = ""
}

/// 贴纸数据模型
struct StickyNoteModel: Codable, Identifiable {
    var id = UUID()
    var pages: [StickyNotePage] = [StickyNotePage(), StickyNotePage(), StickyNotePage()]
    var currentPageIndex: Int = 0
    var frame: NSRect = NSRect(x: 100, y: 100, width: 300, height: 200)
    var opacity: Double = 0.95 // 默认透明度
    
    var currentContent: String {
        get { 
            guard currentPageIndex < pages.count else { return "" }
            return pages[currentPageIndex].content 
        }
        set { 
            if currentPageIndex < pages.count {
                pages[currentPageIndex].content = newValue 
            }
        }
    }
}
