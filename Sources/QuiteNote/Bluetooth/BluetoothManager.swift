import Foundation
import CoreBluetooth

/// 管理 BLE 连接、订阅按钮事件并回写 ACK
final class BluetoothManager: NSObject, ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var connectedDeviceName: String? = nil

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var buttonChar: CBCharacteristic?
    private var ackChar: CBCharacteristic?
    private var lastEvent: (id: UInt8, seq: UInt8, time: Date)?
    var debounceInterval: TimeInterval = 1.0

    /// 初始化 CoreBluetooth 中心管理器
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// 开始扫描并尝试连接自定义服务设备
    func startScanning() {
        central.scanForPeripherals(withServices: [CBUUID(string: "12345678-1234-5678-1234-567812345678")], options: nil)
    }

    /// 断开当前连接并停止扫描
    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        central.stopScan()
        connectedDeviceName = nil
    }

    /// 处理按钮事件载荷并分发到应用
    private func handleButtonEvent(_ data: Data) {
        guard data.count >= 2 else { return }
        let eventId = data[0]
        let seq = data[1]
        // 简单防抖：1 秒内相同事件+序号不重复处理
        if let last = lastEvent {
            if last.id == eventId && last.seq == seq && Date().timeIntervalSince(last.time) < debounceInterval {
                writeAck(status: 0x02, seq: seq)
                return
            }
        }
        lastEvent = (eventId, seq, Date())
        switch eventId {
        case 0x01:
            NotificationCenter.default.post(name: .bluetoothCaptureClipboard, object: seq)
        case 0x02:
            NotificationCenter.default.post(name: .bluetoothToggleHistory, object: seq)
        default:
            break
        }
        writeAck(status: 0x00, seq: seq)
    }

    /// 回写 ACK 给外设，包含状态与序号
    private func writeAck(status: UInt8, seq: UInt8) {
        guard let p = peripheral, let ack = ackChar else { return }
        let payload = Data([status, seq])
        p.writeValue(payload, for: ack, type: .withoutResponse)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    /// 蓝牙状态变更回调
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if state == .poweredOn { startScanning() }
    }

    /// 扫描到设备回调：尝试连接
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    /// 连接成功回调：发现服务
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDeviceName = peripheral.name
        peripheral.discoverServices([CBUUID(string: "12345678-1234-5678-1234-567812345678")])
    }

    /// 连接失败或断开回调：清理状态并重试扫描
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedDeviceName = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedDeviceName = nil
        startScanning()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    /// 发现服务回调：继续发现特征
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let service = peripheral.services?.first else { return }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    /// 发现特征回调：订阅按钮事件并记录 ACK 特征
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        service.characteristics?.forEach { c in
            if c.properties.contains(.notify) { buttonChar = c; peripheral.setNotifyValue(true, for: c) }
            if c.properties.contains(.writeWithoutResponse) { ackChar = c }
        }
    }

    /// 接收按钮事件通知
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        guard let data = characteristic.value else { return }
        handleButtonEvent(data)
    }
}

extension Notification.Name {
    static let bluetoothCaptureClipboard = Notification.Name("bluetoothCaptureClipboard")
    static let bluetoothToggleHistory = Notification.Name("bluetoothToggleHistory")
}
