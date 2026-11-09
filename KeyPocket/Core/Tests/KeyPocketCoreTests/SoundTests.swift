import XCTest
import CryptoKit
@testable import KeyPocketCore

final class SoundTests: XCTestCase {
    private func key(type: Int = 0) -> DoorKey {
        DoorKey(id: "synthetic", keyID: 123456, title: "Synthetic", project: "010203", license: "a1b2c3", floor: "7", type: type, expires: 1800000000, enabled: true, remaining: 0, group: "owner_keys", projectName: "Test")
    }
    func testTimedAuthorizationMatchesRecoveredJava() throws {
        XCTAssertEqual(try SoundProtocol.authorization(door: key(), timestamp: 1700000000), "07f3e5a6b")
        XCTAssertEqual(try SoundProtocol.authorization(door: key(type: 100), timestamp: 1700000000), "40a885a6b")
        XCTAssertEqual(SoundProtocol.crc16Modbus(Array("123456789".utf8)), 0x4b37)
    }
    func testSymbolsMatchOriginalNativeLibrary() throws {
        // Captured by execution-free-to-host AArch64 emulation of the supplied
        // APK's vpp_convertTextToCodes; synthetic inputs, no device/audio/network.
        let fixtures: [String: [Int]] = [
            "012345678": [9,0,1,2,3,4,5,6,7,8,9,7,15,14,18,8,6,0],
            "000000000": [9,0,1,17,18,1,17,18,1,17,18,2,9,8,3,14,4,0],
            "fffffffff": [9,0,16,17,18,16,17,18,16,17,18,7,11,16,10,3,2,0],
            "0706b1d2b": [9,0,1,8,18,7,12,2,14,3,12,6,14,10,9,18,12,0],
            "401234567": [9,0,5,1,2,3,4,5,6,7,8,11,3,17,15,10,1,0]
        ]
        for (hex, symbols) in fixtures { XCTAssertEqual(try SoundProtocol.symbols(hex: hex), symbols) }
    }
    func testAllThreePCMStreamsMatchOriginalLibraryByteForByte() throws {
        let hashes: [SoundBand: String] = [
            .low: "127fe1a29de9b2cda6a9bb2f60409889063fef9546c00f61d3ee7a1168c420a0",
            .standard: "24288fc2c682319e1ca7421531eb3f70a5d7c4dee0ed7fc7208e90122742aacd",
            .high: "28e9a878165c7306ed533db234a3d6dc5958c19507f91cc260f18a8323d0226a"
        ]
        for band in SoundBand.allCases {
            let samples = try SoundProtocol.pcm(hex: "012345678", band: band)
            var data = Data()
            for sample in samples { var value = sample.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
            XCTAssertEqual(data.count, 112878)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), hashes[band]!)
        }
    }
    func testWaveHasMono16Bit44100HzHeader() throws {
        let wave = try SoundProtocol.wave(hex: "012345678", band: .standard)
        XCTAssertEqual(wave.count, 112878 + 44)
        XCTAssertEqual(String(data: wave[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wave[8..<16], encoding: .ascii), "WAVEfmt ")
        XCTAssertEqual(Array(wave[22..<24]), [1,0])
        XCTAssertEqual(Array(wave[24..<28]), [0x44,0xac,0,0])
        XCTAssertEqual(Array(wave[34..<36]), [16,0])
        XCTAssertEqual(String(data: wave[36..<40], encoding: .ascii), "data")
    }
    func testExpiredAndUnsupportedKeysCannotGenerateSound() throws {
        for type in [1, 5, 6, 7, 101] { XCTAssertThrowsError(try SoundProtocol.authorization(door: key(type: type), timestamp: 1700000000)) }
        var door = key(); door.expires = 1700000000
        XCTAssertThrowsError(try SoundProtocol.authorization(door: door, timestamp: 1700000000))
        door = key(); door.enabled = false
        XCTAssertThrowsError(try SoundProtocol.authorization(door: door, timestamp: 1700000000))
        door = key(); door.floor = "128"
        XCTAssertThrowsError(try SoundProtocol.authorization(door: door, timestamp: 1700000000))
        XCTAssertThrowsError(try SoundProtocol.symbols(hex: "not-hex!!"))
    }
    func testExistingFavoritesSurviveAudioSettingsUpgrade() throws {
        let old = Data(#"{"alias":"南门","favorite":true,"order":2}"#.utf8)
        var pref = try JSONDecoder().decode(DoorPreference.self, from: old)
        XCTAssertEqual(pref.alias, "南门"); XCTAssertTrue(pref.favorite); XCTAssertEqual(pref.order, 2)
        XCTAssertEqual(pref.transport, .bluetooth); XCTAssertEqual(pref.band, .standard)
        pref.transport = .sound; pref.band = .low
        let saved = try JSONDecoder().decode(DoorPreference.self, from: JSONEncoder().encode(pref))
        XCTAssertEqual(saved.transport, .sound); XCTAssertEqual(saved.band, .low); XCTAssertEqual(saved.alias, "南门")
    }
}
