#!/usr/bin/env python3
"""Run the same core tests with command-line Swift when XCTest is unavailable.

This adapter supplies assertions and invokes the XCTest test methods unchanged;
it makes no network or Bluetooth connections. Full Xcode can run `swift test`.
"""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
shim = r'''
import Foundation
var failures = 0
class XCTestCase { func setUp() {} ; func tearDown() {} }
func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL \(file):\(line) \(message)")
}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let left = try a(), right = try b(); if left != right { XCTFail("\(left) != \(right) \(message)", file: file, line: line) } }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { XCTFail("Expected true", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { XCTFail("Expected false", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); XCTFail("Expected error", file: file, line: line) } catch {}
}
'''
runner = r'''
import Foundation
@main struct Verify {
    static func main() async {
        let core = ProtocolTests()
        do {
            try core.testChallengeMatchesJava()
            try core.testPayloadMatchesJavaForEachSupportedFamily()
            try core.testAESMatchesJavaAndRoundTripsUnicode()
            try core.testRejectExpiredDisabledInvalidAndVisitorKeys()
            core.testDiscoveryIsBoundToSelectedProjectAndLicense()
            try core.testParserUnderstandsJSONStringArraysAndGroupMasks()
        } catch { XCTFail("Protocol tests: \(error)") }
        let sound = SoundTests()
        do {
            try sound.testTimedAuthorizationMatchesRecoveredJava()
            try sound.testSymbolsMatchOriginalNativeLibrary()
            try sound.testAllThreePCMStreamsMatchOriginalLibraryByteForByte()
            try sound.testWaveHasMono16Bit44100HzHeader()
            try sound.testExpiredAndUnsupportedKeysCannotGenerateSound()
            try sound.testExistingFavoritesSurviveAudioSettingsUpgrade()
        } catch { XCTFail("Sound tests: \(error)") }
        let api = APITests()
        let cases: [() async throws -> Void] = [api.testSMSUsesNestedEncryptedTimestampAndFormEncoding, api.testRefreshCarriesAccountAndReadsRotatedToken, api.testExpiredSessionIsSurfaced, api.testMissingAuthorizationCollectionClearsGrants, api.testSessionOnlyLoginThenAuthorizedKeyRefresh, api.testLoginStillRejectsMissingToken]
        for test in cases {
            api.setUp()
            do { try await test() } catch { XCTFail("API tests: \(error)") }
            api.tearDown()
        }
        print("18 test cases; \(failures) failures. No live network or Bluetooth used.")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
with tempfile.TemporaryDirectory(prefix="keypocket-verify-") as directory:
    temp = pathlib.Path(directory)
    paths = list((root / "Core/Sources/KeyPocketCore").glob("*.swift"))
    for test in (root / "Core/Tests/KeyPocketCoreTests").glob("*.swift"):
        text = test.read_text().replace("import XCTest", "import Foundation").replace("@testable import KeyPocketCore", "")
        dest = temp / test.name
        dest.write_text(text)
        paths.append(dest)
    (temp / "Assertions.swift").write_text(shim)
    (temp / "Runner.swift").write_text(runner)
    executable = temp / "verify"
    subprocess.run(["swiftc", "-swift-version", "5", *map(str, paths), str(temp / "Assertions.swift"), str(temp / "Runner.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
