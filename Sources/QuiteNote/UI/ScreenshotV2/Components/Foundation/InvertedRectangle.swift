import SwiftUI

/// 反向矩形形状：用于在交互层"挖孔"，让特定区域的事件穿透到桌面
struct InvertedRectangle: Shape {
    let hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let hole = hole {
            path.addRect(hole)
        }
        return path
    }
}
