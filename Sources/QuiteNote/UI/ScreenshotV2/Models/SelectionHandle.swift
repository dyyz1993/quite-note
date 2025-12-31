import SwiftUI

/// 选区调整手柄
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: rect.width / 2, y: 0)
        case .topRight: return CGPoint(x: rect.width, y: 0)
        case .right: return CGPoint(x: rect.width, y: rect.height / 2)
        case .bottomRight: return CGPoint(x: rect.width, y: rect.height)
        case .bottom: return CGPoint(x: rect.width / 2, y: rect.height)
        case .bottomLeft: return CGPoint(x: 0, y: rect.height)
        case .left: return CGPoint(x: 0, y: rect.height / 2)
        }
    }
}
