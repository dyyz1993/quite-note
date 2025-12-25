import SwiftUI
import CoreBluetooth

/// 蓝牙设置标签页视图
struct BluetoothSettingsTab: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            statusSection
            deviceListSection
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 16) {
            statusIcon
                .font(.system(size: 32))
                .frame(width: 56, height: 56)
                .background(statusBackgroundColor.opacity(0.2))
                .cornerRadius(28)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                Text(statusDescription)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }

            Spacer()

            if bluetooth.state == .poweredOn && bluetooth.connectedDeviceName == nil {
                Button(action: {
                    bluetooth.startScanning()
                }) {
                    HStack(spacing: 6) {
                        LucideView(name: .search, size: 14, color: .white)
                        Text("扫描设备")
                    }
                    .font(.themeBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeBlue600)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05) as Color))
    }

    private var statusIcon: some View {
        switch bluetooth.state {
        case .poweredOn:
            if let _ = bluetooth.connectedDeviceName {
                LucideView(name: .bluetoothConnected, size: 28, color: .themeGreen500)
            } else {
                LucideView(name: .bluetooth, size: 28, color: .themeYellow500)
            }
        case .poweredOff:
            LucideView(name: .bluetoothOff, size: 28, color: .themeRed500)
        case .unauthorized:
            LucideView(name: .alertTriangle, size: 28, color: .themeRed500)
        default:
            LucideView(name: .bluetoothOff, size: 28, color: .themeTextTertiary)
        }
    }

    private var statusBackgroundColor: Color {
        switch bluetooth.state {
        case .poweredOn:
            return bluetooth.connectedDeviceName != nil ? .themeGreen500 : .themeYellow500
        case .poweredOff, .unauthorized:
            return .themeRed500
        default:
            return .themeTextTertiary
        }
    }

    private var statusText: String {
        switch bluetooth.state {
        case .poweredOn:
            return bluetooth.connectedDeviceName != nil ? "已连接" : "蓝牙已开启"
        case .poweredOff:
            return "蓝牙已关闭"
        case .unauthorized:
            return "未授权"
        default:
            return "未知状态"
        }
    }

    private var statusDescription: String {
        switch bluetooth.state {
        case .poweredOn:
            return bluetooth.connectedDeviceName != nil ? "已连接到 \(bluetooth.connectedDeviceName ?? "")" : "点击扫描设备"
        case .poweredOff:
            return "请在系统设置中开启蓝牙"
        case .unauthorized:
            return "请在系统设置中允许蓝牙访问"
        default:
            return "蓝牙状态异常"
        }
    }

    // MARK: - Device List Section

    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LucideView(name: .database, size: 16, color: .themeBlue400)
                Text("发现的设备")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }

            if bluetooth.discoveredPeripherals.isEmpty {
                emptyStateView
            } else {
                deviceListView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .opacity(0.3)
            Text("未发现设备")
                .font(.themeBody)
                .foregroundColor(.themeTextTertiary)
            Text("确保设备已开启并在附近")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.themeGray800.opacity(0.2) as Color)
        .cornerRadius(12)
    }

    private var deviceListView: some View {
        VStack(spacing: 8) {
            ForEach(bluetooth.discoveredPeripherals, id: \.identifier) { peripheral in
                DeviceRow(peripheral: peripheral, bluetooth: bluetooth)
            }
        }
    }
}

// MARK: - Device Row Component

struct DeviceRow: View {
    let peripheral: CBPeripheral
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        Button(action: {
            bluetooth.connect(to: peripheral)
        }) {
            HStack(spacing: 12) {
                LucideView(name: .cpu, size: 20, color: .themeBlue400)
                    .frame(width: 36, height: 36)
                    .background(Color.themeBlue600.opacity(0.2))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(peripheral.name ?? "未知设备")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Text(peripheral.identifier.uuidString.prefix(8))
                        .font(.themeCaptionSmall)
                        .monospaced()
                        .foregroundColor(.themeTextTertiary)
                }

                Spacer()

                if bluetooth.connectedDeviceName == peripheral.name {
                    LucideView(name: .check, size: 16, color: .themeGreen500)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
