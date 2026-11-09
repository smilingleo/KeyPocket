import XCTest
@testable import KeyPocketCore

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class APITests: XCTestCase {
    var api: KeybootAPI!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        api = KeybootAPI(session: URLSession(configuration: config))
    }
    override func tearDown() { StubProtocol.handler = nil; api = nil }
    func envelope(_ object: [String: Any]) throws -> Data { Data(try APIEnvelope.encrypt(JSONSerialization.data(withJSONObject: object)).utf8) }
    func fields(_ request: URLRequest) throws -> [String: Any] {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096); var data = Data()
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }; body = data
        }
        let text = String(data: body!, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("jiami_data="))
        let base64 = String(text.dropFirst("jiami_data=".count)).removingPercentEncoding!
        return try JSONSerialization.jsonObject(with: APIEnvelope.decrypt(base64)) as! [String: Any]
    }
    func testSMSUsesNestedEncryptedTimestampAndFormEncoding() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/captcha01")
            let fields = try self.fields(request)
            XCTAssertEqual(fields["mobile"] as? String, "13800000000")
            XCTAssertEqual(String(data: try APIEnvelope.decrypt(fields["timestamp"] as! String), encoding: .utf8), "1700000000")
            return try self.envelope(["code": 100, "msg": "sent"])
        }
        try await api.sendCode(mobile: "13800000000", now: 1700000000)
    }
    func testRefreshCarriesAccountAndReadsRotatedToken() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/renew02")
            let fields = try self.fields(request)
            XCTAssertEqual(fields["token"] as? String, "synthetic-token")
            XCTAssertEqual(fields["device_id"] as? String, "device")
            return try self.envelope(["code": "100", "token": "rotated", "servertime": "1700000000", "owner_keys": [], "gate_keys": []])
        }
        let result = try await api.refresh(Account(mobile: "13800000000", token: "synthetic-token", deviceID: "device"))
        XCTAssertEqual(result.token, "rotated"); XCTAssertEqual(result.serverTime, 1700000000); XCTAssertTrue(result.doors.isEmpty)
    }
    func testExpiredSessionIsSurfaced() async throws {
        StubProtocol.handler = { _ in try self.envelope(["code": "-400", "msg": "expired"]) }
        do { _ = try await api.refresh(Account(mobile: "13800000000", token: "expired", deviceID: "device")); XCTFail("Expected failure") }
        catch let error as ServiceError { XCTAssertEqual(error.code, "-400") }
    }
    func testMissingAuthorizationCollectionClearsGrants() async throws {
        StubProtocol.handler = { _ in try self.envelope(["code": "100", "servertime": 1700000000]) }
        let response = try await api.refresh(Account(mobile: "13800000000", token: "test", deviceID: "device"))
        XCTAssertTrue(response.doors.isEmpty)
        XCTAssertFalse(response.hasKeyCollections)
    }
    func testSessionOnlyLoginThenAuthorizedKeyRefresh() async throws {
        var paths: [String] = []
        StubProtocol.handler = { request in
            let path = request.url!.path
            paths.append(path)
            if path == "/auth" {
                return try self.envelope(["code": 100, "token": "session-only", "mobile": "13800000000"])
            }
            XCTAssertEqual(path, "/renew02")
            XCTAssertEqual(try self.fields(request)["token"] as? String, "session-only")
            let key: [String: Any] = ["id": 123, "type": 0, "end_time": 1800000000, "project_license": "010203", "license": "a1b2c3", "floor_station": "7"]
            return try self.envelope(["code": 100, "servertime": 1700000000, "owner_keys": [key]])
        }
        let account = try await api.login(mobile: "13800000000", code: "123456", deviceID: "test-device")
        XCTAssertEqual(account.token, "session-only")
        let response = try await api.refresh(account)
        XCTAssertEqual(paths, ["/auth", "/renew02"])
        XCTAssertEqual(response.doors.count, 1)
        XCTAssertTrue(response.hasKeyCollections)
    }
    func testLoginStillRejectsMissingToken() async throws {
        StubProtocol.handler = { _ in try self.envelope(["code": 100]) }
        do { _ = try await api.login(mobile: "13800000000", code: "123456", deviceID: "device"); XCTFail("Expected missing token failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("令牌")) }
    }
}
