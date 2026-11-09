import Foundation

import CommonCrypto

public enum PocketError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

// Wire constants recovered from the supplied APK, not account credentials.
public enum APIEnvelope {
    private static let key = Array("a49b75a814d505b048ab23546fcdba0d".utf8)
    private static let iv = Array("bdc1946f73e6a3d7".utf8)
    public static func encrypt(_ data: Data) throws -> String { try crypt(data, operation: CCOperation(kCCEncrypt)).base64EncodedString() }
    public static func decrypt(_ text: String) throws -> Data {
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters), !data.isEmpty else { throw PocketError.invalid("服务器返回了无法识别的数据") }
        return try crypt(data, operation: CCOperation(kCCDecrypt))
    }
    private static func crypt(_ data: Data, operation: CCOperation) throws -> Data {
        var output = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var length = 0
        let capacity = output.count
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { input in
                    CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count, ivBytes.baseAddress, input.baseAddress, data.count, &output, capacity, &length)
                }
            }
        }
        guard status == kCCSuccess else { throw PocketError.invalid("协议加解密失败 (\(status))") }
        return Data(output.prefix(length))
    }
}

public struct DoorKey: Codable, Identifiable, Equatable {
    public var id: String
    public var keyID: Int64
    public var title: String
    public var project: String
    public var license: String
    public var floor: String
    public var type: Int
    public var expires: Int64
    public var enabled: Bool
    public var remaining: Int
    public var group: String
    public var projectName: String
    public var supportsBluetooth: Bool { [0, 3, 5, 6, 7, 100].contains(type) }
    public var supportsSound: Bool { [0, 3, 100].contains(type) }
    public func validate(now: Int64) throws {
        guard enabled, expires > now else { throw PocketError.invalid("这把钥匙已过期或已停用，请刷新钥匙") }
        guard supportsBluetooth else { throw PocketError.invalid("此钥匙类型暂不支持；访客次数钥匙与声波设备请使用官方 App") }
        guard keyID >= 0 || type == 5 else { throw PocketError.invalid("钥匙编号无效") }
        _ = try BLEProtocol.hex3(project)
        _ = try BLEProtocol.hex3(license)
        if type == 5 {
            guard UInt64(floor, radix: 16) != nil else { throw PocketError.invalid("楼层授权格式错误") }
        } else if ![3, 100].contains(type) {
            // The APK uses a Java int shift, then sign-extends to 64 bits.
            // Limit to floors with unambiguous positive masks in this implementation.
            guard let number = Int(floor), (1...31).contains(number) else { throw PocketError.invalid("此楼层编码需要额外适配") }
        }
    }
}

public enum KeyParser {
    public static func parse(_ response: [String: Any]) throws -> [DoorKey] {
        var result: [DoorKey] = []
        for group in ["owner_keys", "gate_keys", "visitor_keys"] {
            guard let value = response[group] else { continue }
            let rows: [[String: Any]]
            if let array = value as? [[String: Any]] { rows = array }
            else if let string = value as? String, let data = string.data(using: .utf8), let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] { rows = array }
            else if value is NSNull { continue }
            else { throw PocketError.invalid("钥匙列表格式不兼容：\(group)") }
            for row in rows {
                func s(_ key: String) -> String { string(row[key]) }
                guard let type = Int(s("type")), let expiry = Int64(s("end_time")) else { throw PocketError.invalid("钥匙缺少类型或有效期") }
                let name = [s("project_name"), s("build_num"), s("unit_num"), s("lift_num"), s("floor_num")].filter { !$0.isEmpty }.joined(separator: " · ")
                let ids = row["ids"] as? [Any] ?? []
                let licenses = row["licenses"] as? [Any] ?? []
                let floors = row["floor_stations"] as? [Any] ?? []
                let count = type == 5 ? licenses.count : 1
                if type == 5 && (count == 0 || floors.count != count || ids.count != count) { throw PocketError.invalid("组合钥匙数据不完整") }
                for index in 0..<count {
                    let rawID = type == 5 ? string(ids[index]) : s("id")
                    guard let keyID = Int64(rawID) else { throw PocketError.invalid("钥匙编号缺失") }
                    let license = type == 5 ? string(licenses[index]) : (type == 100 ? "000000" : s("license"))
                    let floor = type == 5 ? string(floors[index]) : (type == 100 ? "0" : s("floor_station"))
                    result.append(DoorKey(id: "\(group):\(rawID):\(index)", keyID: keyID, title: name.isEmpty ? "门 \(rawID)" : name + (count > 1 ? " · \(index + 1)" : ""), project: s("project_license").lowercased(), license: license.lowercased(), floor: floor, type: type, expires: expiry, enabled: s("enable") != "0", remaining: Int(s("remain_times")) ?? 0, group: group, projectName: s("project_name")))
                }
            }
        }
        guard Set(result.map(\.id)).count == result.count else { throw PocketError.invalid("服务器返回重复钥匙，请重新刷新") }
        return result
    }
    public static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }
}

public enum BLEProtocol {
    private static let authenticationKey: [UInt32] = [-1565027521, -2137322548, 583228547, -420656679].map { UInt32(truncatingIfNeeded: $0) }
    private static let payloadKey: [UInt32] = [1783677750, 1142738275, -1974410777, -484077794].map { UInt32(truncatingIfNeeded: $0) }
    public static func hex3(_ text: String) throws -> [UInt8] {
        guard text.count == 6 else { throw PocketError.invalid("门禁授权编码必须为六位十六进制") }
        let chars = Array(text)
        return try stride(from: 0, to: 6, by: 2).map { i in
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { throw PocketError.invalid("门禁授权编码无效") }; return byte
        }
    }
    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << UInt32(8 * $1) }
    }
    public static func tea(_ block: [UInt8], key: [UInt32]) throws -> [UInt8] {
        guard block.count == 8, key.count == 4 else { throw PocketError.invalid("TEA 数据长度错误") }
        var a = word(block, 0), b = word(block, 4), sum: UInt32 = 0
        for _ in 0..<32 {
            sum = sum &+ 0x9e3779b9
            a = a &+ (((b << 4) &+ key[0]) ^ (b &+ sum) ^ ((b >> 5) &+ key[1]))
            b = b &+ (((a << 4) &+ key[2]) ^ (a &+ sum) ^ ((a >> 5) &+ key[3]))
        }
        return [a, b].flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    }
    public static func challenge(_ data: Data) throws -> (token: [UInt8], response: Data) {
        guard data.count == 18 else { throw PocketError.invalid("门禁挑战数据长度不兼容") }
        let token = Array(data[8..<16].reversed())
        let encrypted = try tea(token, key: authenticationKey)
        var frame: [UInt8] = [0x55, 0xaa, 0x12, 0xc5, 0, 0, 0, 0] + encrypted.reversed() + [0x33]
        frame.append(frame.reduce(0, ^))
        return (token, Data(frame))
    }
    public static func plaintext(door: DoorKey, timestamp: Int64) throws -> [UInt8] {
        try door.validate(now: timestamp)
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes[0...2] = [1, 1, 1]
        bytes[3] = door.type == 100 ? 1 : ([3, 5].contains(door.type) ? 5 : 0)
        bytes.replaceSubrange(5..<8, with: try hex3(door.project))
        bytes.replaceSubrange(9..<12, with: try hex3(door.license))
        let id = UInt64(bitPattern: door.type == 5 ? -1 : door.keyID)
        for i in 0..<4 { bytes[12+i] = UInt8(truncatingIfNeeded: id >> (i * 8)) }
        let mask: UInt64
        if door.type == 3 { mask = UInt64.max }
        else if door.type == 5 { mask = UInt64(door.floor, radix: 16)! }
        else if door.type == 100 { mask = 0xffffffff80000000 } // Java: 1 << (0 - 1), widened to long.
        else { mask = UInt64(1) << (Int(door.floor)! - 1) }
        for i in 0..<8 { bytes[27-i] = UInt8(truncatingIfNeeded: mask >> (i * 8)) }
        for i in 0..<4 { bytes[28+i] = UInt8(truncatingIfNeeded: timestamp >> (i * 8)) }
        bytes[32] = 0xaa
        return bytes
    }
    public static func payload(door: DoorKey, timestamp: Int64, token: [UInt8]) throws -> Data {
        guard token.count == 8 else { throw PocketError.invalid("门禁会话令牌长度错误") }
        let plain = try plaintext(door: door, timestamp: timestamp)
        let sessionKey = [authenticationKey[0], authenticationKey[1], word(token, 0), word(token, 4)]
        var output: [UInt8] = []
        for start in stride(from: 0, to: 40, by: 8) {
            let first = try tea(Array(plain[start..<start+8].reversed()), key: payloadKey)
            output += try tea(first, key: sessionKey)
        }
        return Data(output)
    }
    public static func matches(name: String, door: DoorKey) -> Bool {
        let name = name.lowercased()
        guard name.count == 14 else { return false }
        if name.hasPrefix("2" + door.project) { return true }
        if door.type == 100 { return name.hasPrefix("1" + door.project) }
        return name == "1" + door.project + door.license + "a"
    }
}
