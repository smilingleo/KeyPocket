import Foundation

public enum DoorTransport: String, Codable, CaseIterable {
    case bluetooth, sound
    public var title: String { self == .bluetooth ? "蓝牙" : "声波（手机扬声器）" }
}

public enum SoundBand: String, Codable, CaseIterable {
    case standard, low, high
    public var baseFrequency: Int { switch self { case .standard: return 12200; case .low: return 9000; case .high: return 17000 } }
    public var title: String { switch self { case .standard: return "标准频段"; case .low: return "低频兼容"; case .high: return "高频" } }
}

public enum SoundProtocol {
    public static let sampleRate = 44100
    private static let authorizationKey: [UInt32] = [101122824, 17236489, 134677250, 17238274]
    private static let alpha: [UInt8] = [1, 2, 4, 8, 3, 6, 12, 11, 5, 10, 7, 14, 15, 13, 9]
    private static let logarithm = [15, 0, 1, 4, 2, 8, 5, 10, 3, 14, 9, 7, 6, 13, 11, 12]

    public static func validate(_ door: DoorKey, timestamp: Int64) throws {
        guard door.enabled, door.expires > timestamp else { throw PocketError.invalid("这把钥匙已过期或已停用，请刷新钥匙") }
        guard door.supportsSound else { throw PocketError.invalid("此钥匙不支持已验证的声波协议，请选择蓝牙") }
        guard door.keyID >= 0 else { throw PocketError.invalid("钥匙编号无效") }
        _ = try BLEProtocol.hex3(door.type == 100 ? door.project : door.license)
        if door.type != 100 {
            guard let floor = Int(door.floor.isEmpty ? "0" : door.floor), (0...127).contains(floor) else { throw PocketError.invalid("此楼层编码尚不支持声波") }
        }
    }
    public static func authorization(door: DoorKey, timestamp: Int64) throws -> String {
        try validate(door, timestamp: timestamp)
        let license = try BLEProtocol.hex3(door.type == 100 ? door.project : door.license)
        let reversed = Array(license.reversed())
        let plain = reversed + reversed + [UInt8(timestamp % 60), 0]
        let encrypted = try BLEProtocol.tea(plain, key: authorizationKey)
        let checksum = crc16Modbus(encrypted)
        let minute = ((timestamp / 60) % 1440) * 2 + 1
        let floor = door.type == 100 ? 0x40 : Int(door.floor.isEmpty ? "0" : door.floor)!
        return String(format: "%02x%04x%03x", floor, Int(checksum), Int(minute))
    }
    public static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xa001 : crc >> 1 }
        }
        return crc
    }
    private static func crc16CCITT(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }
    private static func multiply(_ value: UInt8, byAlpha power: Int) -> UInt8 {
        value == 0 ? 0 : alpha[(logarithm[Int(value)] + power) % 15]
    }
    public static func symbols(hex: String) throws -> [Int] {
        guard hex.count == 9 else { throw PocketError.invalid("声波授权数据长度无效") }
        var data = try hex.map { char -> UInt8 in
            guard let value = UInt8(String(char), radix: 16) else { throw PocketError.invalid("声波授权数据无效") }; return value
        }
        let crc = crc16CCITT(data)
        data += [12, 8, 4, 0].map { UInt8((crc >> $0) & 15) }
        // Recovered shortened RS(15,13) over GF(16), primitive polynomial x^4+x+1.
        // The APK encodes the thirteen nibbles in reverse order; parity is appended.
        var p0: UInt8 = 0, p1: UInt8 = 0
        for nibble in data.reversed() {
            let feedback = p1 ^ nibble
            p1 = p0 ^ multiply(feedback, byAlpha: 5)
            p0 = multiply(feedback, byAlpha: 3)
        }
        data += [p0, p1]
        var output = [9, 0]
        var previous = -1, beforePrevious = -1
        for nibble in data {
            let value = Int(nibble)
            let next: Int
            if value == previous { next = 17 }
            else if value == beforePrevious { next = previous == 18 ? 17 : 18 }
            else { next = value }
            output.append(next == 17 || next == 18 ? next : next + 1)
            beforePrevious = previous; previous = next
        }
        output.append(0)
        return output
    }
    public static func pcm(hex: String, band: SoundBand) throws -> [Int16] {
        let codes = try symbols(hex: hex)
        let count = 65 * sampleRate / 1000
        let padding = Int(Double(count) * 0.08)
        let ramp = Int(Double(count - 2 * padding) * 0.3)
        let rampEnd = padding + ramp
        let fallEnd = count - padding
        let amplitude = Int(Double(32768) * 0.99)
        let slope = Float(amplitude) / Float(ramp)
        var samples = [Int16](repeating: 0, count: 10 * sampleRate / 1000)
        samples.reserveCapacity(samples.count + codes.count * count + sampleRate / 10)
        for code in codes {
            let frequency = band.baseFrequency + code * 150
            let ratio = Float(frequency) / Float(sampleRate)
            let step = Float(Double(ratio + ratio) * Double.pi)
            var phase: Float = 0
            for i in 0..<count {
                let gain: Int
                if i < padding || i > fallEnd + 1 { gain = 0 }
                else if i > count - rampEnd + 1 { gain = Int(Float(fallEnd - i) * slope) }
                else if i < rampEnd { gain = Int(Float(i - padding) * slope) }
                else { gain = amplitude }
                let sample = Int(sin(Double(phase)) * Double(gain) + 0.5)
                samples.append(Int16(clamping: sample))
                phase += step
            }
        }
        samples += [Int16](repeating: 0, count: sampleRate / 10)
        return samples
    }
    public static func wave(hex: String, band: SoundBand) throws -> Data {
        let samples = try pcm(hex: hex, band: band)
        var data = Data()
        func text(_ text: String) { data.append(contentsOf: text.utf8) }
        func u32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        func u16(_ value: UInt16) { data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8)) }
        text("RIFF"); u32(UInt32(samples.count * 2 + 36)); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(samples.count * 2))
        for sample in samples { u16(UInt16(bitPattern: sample)) }
        return data
    }
}
