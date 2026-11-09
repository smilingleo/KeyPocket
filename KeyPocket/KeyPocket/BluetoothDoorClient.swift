import Foundation
import CoreBluetooth
import Combine
import KeyPocketCore

@MainActor
final class BluetoothDoorClient: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var status = "等待开门"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var pending: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var door: DoorKey?
    private var clock: (() -> Int64)?
    private var session = UUID()
    private var phase = "idle"
    private var token: [UInt8] = []
    private var chunks: [Data] = []
    private var command: CBCharacteristic?
    private var commandStarted = false
    private var retryAllowed = false
    private let service = CBUUID(string: "FFC0")
    private let challengeID = CBUUID(string: "FFC1")
    private let authID = CBUUID(string: "FFC2")
    private let commandID = CBUUID(string: "FFC3")

    func open(_ door: DoorKey, clock: @escaping () -> Int64) async throws {
        for attemptNumber in 1...2 {
            do { try await attempt(door, clock: clock); return }
            catch {
                guard attemptNumber == 1, retryAllowed, !Task.isCancelled else { throw error }
                status = "连接尚未发送开门数据，正在重试一次…"
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
    private func attempt(_ door: DoorKey, clock: @escaping () -> Int64) async throws {
        retryAllowed = false
        guard pending == nil else { throw PocketError.invalid("已有开门请求正在进行") }
        try Task.checkCancellation()
        try door.validate(now: clock())
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.pending = continuation
                self.door = door; self.clock = clock; self.session = UUID()
                self.commandStarted = false; self.retryAllowed = false
                self.phase = "waiting"
                self.status = "正在准备蓝牙…"
                self.timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 6_000_000_000) } catch { return }
                    self?.finish(.failure(PocketError.invalid("蓝牙开门超时。请靠近门禁，或在配置中为支持的门选择声波")), retryable: true)
                }
                if self.central == nil { self.central = CBCentralManager(delegate: self, queue: .main) }
                else { self.startIfReady() }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.cancel() } })
    }
    func cancel() { finish(.failure(CancellationError())) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { startIfReady() }
    private func startIfReady() {
        guard pending != nil else { return }
        switch central.state {
        case .poweredOn:
            guard phase == "waiting" else { return }
            phase = "scanning"; status = "正在寻找所选门禁…"
            // Legacy controllers may omit their service UUID in advertisements.
            // Discovery is passive; only names matching the selected authorized key connect.
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .poweredOff: finish(.failure(PocketError.invalid("请先打开蓝牙")))
        case .unauthorized: finish(.failure(PocketError.invalid("请在当前设备的设置中允许钥匙口袋使用蓝牙")))
        case .unsupported: finish(.failure(PocketError.invalid("此设备不支持蓝牙门禁")))
        case .unknown, .resetting: break
        @unknown default: finish(.failure(PocketError.invalid("蓝牙暂不可用")))
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover found: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard phase == "scanning", let door, RSSI.intValue > -85, RSSI.intValue < 0,
              let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? found.name,
              BLEProtocol.matches(name: name, door: door) else { return }
        central.stopScan(); peripheral = found; found.delegate = self
        phase = "connecting"; status = "正在连接所选门禁…"
        central.connect(found, options: nil)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral, pending != nil else { return }
        phase = "discovering"; status = "正在验证门禁…"
        peripheral.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        finish(.failure(error ?? PocketError.invalid("无法连接门禁")), retryable: true)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral, pending != nil else { return }
        // Some controllers disconnect immediately after the final write ACK.
        // All data has then been acknowledged: report sent, never resend it.
        if phase == "finishing" { finish(.success(())); return }
        finish(.failure(error ?? PocketError.invalid("连接已中断，未确认请求发送完成")), retryable: true)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral, pending != nil else { return }
        if let error { finish(.failure(error)); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == self.service }) else { finish(.failure(PocketError.invalid("此门禁未提供兼容的蓝牙服务"))); return }
        peripheral.discoverCharacteristics([challengeID, authID, commandID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral, pending != nil else { return }
        if let error { finish(.failure(error)); return }
        guard let characteristics = service.characteristics,
              let challenge = characteristics.first(where: { $0.uuid == challengeID }),
              let auth = characteristics.first(where: { $0.uuid == authID }),
              let command = characteristics.first(where: { $0.uuid == commandID }),
              challenge.properties.contains(.read), auth.properties.contains(.write), command.properties.contains(.write)
        else { finish(.failure(PocketError.invalid("此门禁的蓝牙特征不兼容"))); return }
        self.command = command; phase = "reading"
        peripheral.readValue(for: challenge)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, phase == "reading", characteristic.uuid == challengeID else { return }
        if let error { finish(.failure(error)); return }
        do {
            guard let data = characteristic.value,
                  let auth = characteristic.service?.characteristics?.first(where: { $0.uuid == authID }) else { throw PocketError.invalid("缺少门禁挑战数据") }
            let challenge = try BLEProtocol.challenge(data)
            token = challenge.token; phase = "authenticating"
            peripheral.writeValue(challenge.response, for: auth, type: .withResponse)
        } catch { finish(.failure(error)) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, pending != nil else { return }
        if let error { finish(.failure(error)); return }
        do {
            if phase == "authenticating", characteristic.uuid == authID {
                guard let door, let clock else { throw PocketError.invalid("开门会话已结束") }
                let payload = try BLEProtocol.payload(door: door, timestamp: clock(), token: token)
                chunks = stride(from: 0, to: payload.count, by: 20).map { payload.subdata(in: $0..<min($0+20, payload.count)) }
                phase = "writing"; status = "正在发送开门请求…"
                sendNext(after: 30_000_000)
            } else if phase == "writing", characteristic.uuid == commandID {
                if chunks.isEmpty {
                    phase = "finishing"
                    let current = session
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard let self, current == self.session, self.pending != nil else { return }
                        self.finish(.success(()))
                    }
                }
                else { sendNext(after: 20_000_000) }
            }
        } catch { finish(.failure(error)) }
    }
    private func sendNext(after delay: UInt64) {
        let current = session
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, current == self.session, self.pending != nil, self.phase == "writing",
                  let peripheral = self.peripheral, let command = self.command, !self.chunks.isEmpty else { return }
            self.commandStarted = true
            peripheral.writeValue(self.chunks.removeFirst(), for: command, type: .withResponse)
        }
    }
    private func finish(_ result: Result<Void, Error>, retryable: Bool = false) {
        guard let continuation = pending else { return }
        retryAllowed = retryable && !commandStarted && central?.state == .poweredOn
        pending = nil; timeout?.cancel(); timeout = nil
        central?.stopScan()
        if let peripheral { peripheral.delegate = nil; central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; door = nil; clock = nil; token = []; chunks = []; command = nil
        phase = "idle"; session = UUID()
        switch result {
        case .success: status = "请求已发送，请确认门已打开"
        case .failure(let error): status = error is CancellationError ? "已取消" : error.localizedDescription
        }
        continuation.resume(with: result)
    }
}
