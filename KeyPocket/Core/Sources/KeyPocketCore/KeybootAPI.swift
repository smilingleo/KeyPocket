import Foundation

public struct Account: Codable {
    public var mobile: String
    public var token: String
    public var deviceID: String
    public init(mobile: String, token: String, deviceID: String) { self.mobile = mobile; self.token = token; self.deviceID = deviceID }
}

public struct KeyResponse {
    public var token: String?
    public var mobile: String?
    public var doors: [DoorKey]
    public var serverTime: Int64
    public var hasKeyCollections: Bool
}

public struct ServiceError: LocalizedError {
    public var code: String
    public var message: String
    public var errorDescription: String? { message }
}

public final class KeybootAPI {
    // Exact host and port recovered from constant/e.java. ATS is scoped to this domain.
    public static let endpoint = URL(string: "http://app.keyboot.com:8667/")!
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    private func request(_ path: String, _ fields: [String: Any]) async throws -> [String: Any] {
        let plain = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        let encrypted = try APIEnvelope.encrypt(plain)
        var request = URLRequest(url: Self.endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = ("jiami_data=" + encrypted.addingPercentEncoding(withAllowedCharacters: safe)!).data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 8_000_000,
              let raw = String(data: data, encoding: .utf8) else { throw PocketError.invalid("服务器请求失败") }
        let decoded = try APIEnvelope.decrypt(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let object = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else { throw PocketError.invalid("服务器返回格式不兼容") }
        let code = KeyParser.string(object["code"])
        guard code == "100" else { throw ServiceError(code: code, message: KeyParser.string(object["msg"]).isEmpty ? "请求失败 (\(code))" : KeyParser.string(object["msg"])) }
        return object
    }
    public func sendCode(mobile: String, now: Int64) async throws {
        guard mobile.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil else { throw PocketError.invalid("请输入有效的中国大陆手机号") }
        let timestamp = try APIEnvelope.encrypt(Data(String(now).utf8))
        _ = try await request("captcha01", ["mobile": mobile, "timestamp": timestamp])
    }
    public func login(mobile: String, code: String, deviceID: String) async throws -> Account {
        let result = try await request("auth", ["mobile": mobile, "captcha": code, "device_id": deviceID, "model": "iPhone"])
        let token = KeyParser.string(result["token"])
        guard !token.isEmpty else { throw PocketError.invalid("登录响应缺少令牌") }
        let returnedMobile = KeyParser.string(result["mobile"])
        // Authentication may return only a session. Keys and server time belong
        // to the subsequent renew02 synchronization, not the login contract.
        return Account(mobile: returnedMobile.isEmpty ? mobile : returnedMobile, token: token, deviceID: deviceID)
    }
    public func refresh(_ account: Account) async throws -> KeyResponse {
        var fields = parameters(account)
        fields["model"] = "iPhone"
        fields["appversion"] = "4.5.0"
        return try parse(await request("renew02", fields))
    }
    public func verify(_ door: DoorKey, account: Account) async throws -> String? {
        var fields = parameters(account)
        fields["key_id"] = String(door.keyID)
        fields["license"] = door.project
        let response = try await request("key_verification", fields)
        return response["token"] as? String
    }
    private func parameters(_ account: Account) -> [String: Any] {
        ["mobile": account.mobile, "token": account.token, "device_id": account.deviceID]
    }
    private func parse(_ object: [String: Any]) throws -> KeyResponse {
        guard let serverTime = Int64(KeyParser.string(object["servertime"])), serverTime > 0 else { throw PocketError.invalid("响应缺少服务器时间，无法安全生成限时请求") }
        // The original KeysActivity treats absent collections as empty. Replace
        // the current snapshot with an empty list, never retain stale grants.
        let hasCollections = ["owner_keys", "gate_keys", "visitor_keys"].contains { object[$0] != nil && !(object[$0] is NSNull) }
        return KeyResponse(token: object["token"] as? String, mobile: object["mobile"] as? String, doors: try KeyParser.parse(object), serverTime: serverTime, hasKeyCollections: hasCollections)
    }
}
