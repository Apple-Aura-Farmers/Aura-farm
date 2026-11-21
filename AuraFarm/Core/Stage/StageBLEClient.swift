import CoreBluetooth
import Foundation
import Observation

/// Talks to the Terraloka stage over the Nordic UART service. Everything runs on the main queue.
@Observable
final class StageBLEClient: NSObject {
    enum Status: Equatable {
        case bluetoothUnavailable, unauthorized, idle, scanning, connecting, connected, reconnecting
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
    }

    static let deviceName = "terraloka_stage"
    private static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let rxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let txUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private(set) var status: Status = .idle
    private(set) var mode: StageMode = .manual
    private(set) var runState: StageRunState = .idle
    private(set) var x = 90
    private(set) var y = 90
    private(set) var queued = 0
    private(set) var lastError: String?
    private(set) var log: [LogLine] = []

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var rx: CBCharacteristic?
    @ObservationIgnored private var tx: CBCharacteristic?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var pendingStart = false
    /// Last angle sent (or reported) per axis; not shown, so not observed.
    @ObservationIgnored private(set) var targetX = 90
    @ObservationIgnored private(set) var targetY = 90

    // MARK: Public

    func connect() {
        wantsConnection = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)  // state callback starts the scan
        } else {
            beginIfReady()
        }
    }

    func disconnect() {
        wantsConnection = false
        pendingStart = false
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        rx = nil
        tx = nil
        if status != .bluetoothUnavailable && status != .unauthorized { status = .idle }
    }

    @discardableResult
    func send(_ command: StageCommand) -> Bool {
        let text: String
        do { text = try command.validated() } catch {
            lastError = error.localizedDescription
            return false
        }
        guard status == .connected, let peripheral, let rx else {
            lastError = "Not connected."
            return false
        }
        peripheral.writeValue(Data(text.utf8), for: rx, type: .withResponse)
        append("> \(text)")
        return true
    }

    /// MANUAL: at most one GOTO per axis, and only for axes whose target changed.
    func moveTo(x newX: Int, y newY: Int) {
        if newX != targetX {
            targetX = newX
            send(.goTo(.x, newX))
        }
        if newY != targetY {
            targetY = newY
            send(.goTo(.y, newY))
        }
    }

    /// AUTO: PATH, then START once the device answers "OK PATH".
    func runPath(_ points: [StagePoint]) {
        pendingStart = send(.path(points))
    }

    /// Jog also moves the remembered target, so a later `moveTo` compares against it.
    func jog(_ axis: StageAxis, _ delta: Int) {
        if axis == .x {
            targetX = min(180, max(0, targetX + delta))
        } else {
            targetY = min(180, max(0, targetY + delta))
        }
        send(.jog(axis, delta))
    }

    // MARK: Internals

    private func beginIfReady() {
        guard wantsConnection, let central, central.state == .poweredOn else { return }
        guard status != .connected, status != .connecting, status != .scanning else { return }
        if let peripheral {
            status = .reconnecting
            central.connect(peripheral)
        } else {
            status = .scanning
            central.scanForPeripherals(withServices: nil)
        }
    }

    private func append(_ text: String) {
        log.insert(LogLine(text: text), at: 0)
        if log.count > 100 { log.removeLast(log.count - 100) }
    }

    private func setPosition(_ nx: Int, _ ny: Int) {
        x = nx
        y = ny
        targetX = nx
        targetY = ny
    }

    private func handle(_ line: String) {
        append(line)
        switch StageReply.parse(line) {
        case .ok(let text):
            lastError = nil
            if text == "MODE AUTO" { mode = .auto } else if text == "MODE MANUAL" { mode = .manual }
            if text.hasPrefix("PATH"), pendingStart {
                pendingStart = false
                send(.start)
            }
        case .error(let text):
            lastError = text
            pendingStart = false
        case .position(let nx, let ny):
            x = nx
            y = ny
        case .done(let nx, let ny):
            setPosition(nx, ny)
            runState = .idle
            queued = 0
        case .hello(let m, let s, let nx, let ny):
            mode = m
            runState = s
            setPosition(nx, ny)
        case .resumed(let nx, let ny, let q):
            x = nx
            y = ny
            queued = q
        case .status(let m, let s, let nx, let ny, let q):
            mode = m
            runState = s
            queued = q
            x = nx
            y = ny
            if s == .idle {
                targetX = nx
                targetY = ny
            }
        case .unknown:
            break
        }
    }
}

extension StageBLEClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if status == .bluetoothUnavailable || status == .unauthorized { status = .idle }
            beginIfReady()
        case .unauthorized:
            status = .unauthorized
        default:
            // Powered off / unsupported / resetting: the link is gone; keep the peripheral for later.
            status = .bluetoothUnavailable
            rx = nil
            tx = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi _: NSNumber
    ) {
        let name =
            peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard name == Self.deviceName, wantsConnection else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        status = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = .connecting  // connected only once notifications are on
        peripheral.discoverServices([Self.service])
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        lost(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        lost(peripheral)
    }

    private func lost(_ peripheral: CBPeripheral) {
        rx = nil
        tx = nil
        guard wantsConnection else { return }
        status = .reconnecting
        central?.connect(peripheral)  // iOS keeps this pending until the device is back
    }
}

extension StageBLEClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            lastError = "Stage service not found."
            return
        }
        peripheral.discoverCharacteristics([Self.rxUUID, Self.txUUID], for: s)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.rxUUID { rx = c }
            if c.uuid == Self.txUUID { tx = c }
        }
        if let tx, rx != nil { peripheral.setNotifyValue(true, for: tx) }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.txUUID, characteristic.isNotifying else { return }
        status = .connected
        lastError = nil
        send(.status)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard characteristic.uuid == Self.txUUID, let data = characteristic.value,
            let text = String(data: data, encoding: .utf8)
        else { return }
        for line in text.split(whereSeparator: \.isNewline) { handle(String(line)) }
    }
}
