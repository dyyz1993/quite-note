import SwiftUI

/// 系统“设置”场景复用应用内的完整设置界面，避免两套设置内容不一致。
struct PreferencesView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        SettingsOverlayView(
            store: store,
            bluetooth: bluetooth,
            showSettings: .constant(true),
            allowsDismissal: false
        )
        .frame(minWidth: 760, minHeight: 620)
        .preferredColorScheme(.dark)
    }
}
