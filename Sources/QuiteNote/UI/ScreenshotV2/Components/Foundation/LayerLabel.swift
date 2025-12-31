import SwiftUI

/// 层级标签组件
struct LayerLabel: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(4)
            .padding(10)
    }
}
