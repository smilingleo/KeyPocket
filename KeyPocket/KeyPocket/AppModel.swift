import Foundation
import Combine
import KeyPocketCore


@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private var shortcutTask: Task<Void, Error>?
    @Published private(set) var isDemo = false
    @Published private(set) var account: Account?
    @Published private(set) var doors: [DoorKey] = []
    @Published private(set) var busy = false
    @Published private(set) var opening: String?
    @Published var message = "登录后同步你有权使用的门禁"
    @Published var preferences: [String: DoorPreference] = [:]
    @Published private(set) var codeAvailableAt = Date.distantPast
    let bluetooth = BluetoothDoorClient()
    let sound = SoundDoorClient()
    private let api = KeybootAPI()
    private var serverTime: Int64 = 0
    private var synchronizedAt: TimeInterval = 0
    private var deviceID = ""
    private var activeTask: Task<Void, Never>?
    private var accountPreferenceKey: String { "doorPreferences." + (account?.mobile ?? "signed-out") }
    var favorites: [DoorKey] { doors.filter { preferences[$0.id]?.favorite == true }.sorted { (preferences[$0.id]?.order ?? 0) < (preferences[$1.id]?.order ?? 0) } }

    init() {
        do {
            if let stored = try SecureStorage.read("deviceID"), let id = String(data: stored, encoding: .utf8) { deviceID = id }
            else {
                deviceID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                try SecureStorage.write(Data(deviceID.utf8), key: "deviceID")
            }
            if let data = try SecureStorage.read("account") { account = try JSONDecoder().decode(Account.self, from: data) }
            loadPreferences()
        } catch { message = "无法读取安全存储：\(error.localizedDescription)" }
    }
    func enterDemo() {
        guard account == nil, !busy else { return }
        let rows: [[String: Any]] = [
            ["id":"demo:south", "keyID":-1001, "title":"示例社区 · 南门", "project":"000000", "license":"000000", "floor":"1", "type":0, "expires":1830297600, "enabled":true, "remaining":0, "group":"demo", "projectName":"示例社区"],
            ["id":"demo:lobby", "keyID":-1002, "title":"示例社区 · 单元门", "project":"000000", "license":"000000", "floor":"1", "type":0, "expires":1830297600, "enabled":true, "remaining":0, "group":"demo", "projectName":"示例社区"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: rows), let sample = try? JSONDecoder().decode([DoorKey].self, from: data) else { return }
        isDemo = true
        account = Account(mobile: "演示账户", token: "", deviceID: "demo")
        doors = sample
        preferences = [:]
        for (index, door) in sample.enumerated() {
            var value = DoorPreference(alias: index == 0 ? "小区南门" : "家楼下的门", favorite: true, order: index)
            if index == 1 { value.transport = .sound }
            preferences[door.id] = value
        }
        message = "功能演示使用示例钥匙，不会连接或打开真实门禁。"
    }
    func title(_ door: DoorKey) -> String {
        let alias = preferences[door.id]?.alias.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? door.title : alias
    }
    func preference(_ door: DoorKey) -> DoorPreference { preferences[door.id] ?? DoorPreference(order: preferences.count) }
    func configure(_ door: DoorKey, alias: String? = nil, favorite: Bool? = nil, transport: DoorTransport? = nil, band: SoundBand? = nil) {
        var value = preference(door)
        if let alias { value.alias = String(alias.prefix(60)) }
        if let favorite { value.favorite = favorite }
        if let transport { value.transport = transport }
        if let band { value.band = band }
        preferences[door.id] = value
        savePreferences()
    }
    func moveFavorites(from: IndexSet, to: Int) {
        var list = favorites
        // Match SwiftUI's move semantics without changing server authorization fields.
        let items = from.sorted().map { list[$0] }
        for i in from.sorted(by: >) { list.remove(at: i) }
        let destination = to - from.filter { $0 < to }.count
        list.insert(contentsOf: items, at: destination)
        for (i, door) in list.enumerated() { var pref = preference(door); pref.order = i; preferences[door.id] = pref }
        savePreferences()
    }
    private func loadPreferences() {
        preferences = UserDefaults.standard.data(forKey: accountPreferenceKey).flatMap { try? JSONDecoder().decode([String: DoorPreference].self, from: $0) } ?? [:]
    }
    private func savePreferences() {
        guard !isDemo else { return }
        updateShortcutCatalog()
        if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: accountPreferenceKey) } }
    private func persistAccount() throws {
        guard !isDemo else { return }
        if let account { try SecureStorage.write(try JSONEncoder().encode(account), key: "account") }
    }
    private func absorb(_ response: KeyResponse) throws {
        if let token = response.token, !token.isEmpty { account?.token = token }
        doors = response.doors
        serverTime = response.serverTime
        synchronizedAt = ProcessInfo.processInfo.systemUptime
        try persistAccount()
        updateShortcutCatalog()
    }
    private func syncMessage(_ response: KeyResponse) -> String {
        if !response.hasKeyCollections { return "已登录，但本次同步未返回钥匙数据。可点击右上角刷新重试；当前未启用任何门禁。" }
        if response.doors.isEmpty { return "已登录，同步完成：账户当前没有可用钥匙。" }
        return "已同步 \(response.doors.count) 把钥匙。在配置页选择常用门。"
    }
    private func clock() throws -> Int64 {
        let elapsed = ProcessInfo.processInfo.systemUptime - synchronizedAt
        guard serverTime > 0, elapsed >= 0, elapsed < 120 else { throw PocketError.invalid("服务器时间已过期，请刷新钥匙") }
        return serverTime + Int64(elapsed)
    }
    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        activeTask = Task {
            defer { busy = false; opening = nil; activeTask = nil }
            do { try await operation() }
            catch is CancellationError { message = "已取消" }
            catch {
                if let service = error as? ServiceError, ["-400", "-300"].contains(service.code) {
                    try? SecureStorage.delete("account"); account = nil; doors = []; preferences = [:]; FavoriteDoorEntity.save([]); clearWatchAccount()
                }
                message = error.localizedDescription
            }
        }
    }
    func sendCode(mobile: String) {
        guard !isDemo else { message = "请退出演示后登录"; return }
        guard Date() >= codeAvailableAt else { return }
        run {
            try await self.api.sendCode(mobile: mobile, now: Int64(Date().timeIntervalSince1970))
            self.codeAvailableAt = Date().addingTimeInterval(60)
            self.message = "验证码已发送"
        }
    }
    func login(mobile: String, code: String) {
        guard !isDemo else { message = "请退出演示后登录"; return }
        run {
            guard !self.deviceID.isEmpty, !code.isEmpty else { throw PocketError.invalid("请输入验证码") }
            let account = try await self.api.login(mobile: mobile, code: code, deviceID: self.deviceID)
            try Task.checkCancellation()
            self.account = account
            FavoriteDoorEntity.save([])
            self.doors = []
            try self.persistAccount()
            self.loadPreferences()
            self.message = "登录成功，正在同步钥匙…"
            do {
                let response = try await self.api.refresh(account)
                try Task.checkCancellation()
                try self.absorb(response)
                self.message = self.syncMessage(response)
            } catch {
                if error is CancellationError { throw error }
                if let service = error as? ServiceError, ["-400", "-300"].contains(service.code) { throw error }
                self.message = "登录成功，但钥匙同步失败：\(error.localizedDescription)。可点击右上角刷新重试。"
            }
        }
    }
    func refresh() {
        guard !isDemo else { message = "演示钥匙不会向服务器同步；真实钥匙需登录后获取授权。"; return }
        guard let account else { return }
        run {
            let response = try await self.api.refresh(account)
            try self.absorb(response)
            self.message = self.syncMessage(response)
        }
    }
    func open(_ selected: DoorKey) {
        guard !isDemo else { message = "演示：已展示开门操作。未扫描蓝牙、未播放声波，也未发送真实请求。"; return }
        run { try await self.openAuthorizedDoor(selected.id) }
    }
    private func openAuthorizedDoor(_ doorID: String) async throws {
        guard !isDemo else { throw PocketError.invalid("演示钥匙不能用于真实门禁") }
        guard let account else { throw PocketError.invalid("请先在钥匙口袋中登录") }
            self.opening = doorID
            self.message = "正在检查最新授权…"
            // Refresh before each physical request; revoked keys never use a stale cache.
            try self.absorb(await self.api.refresh(account))
            try Task.checkCancellation()
            guard let door = self.doors.first(where: { $0.id == doorID }) else { throw PocketError.invalid("这把钥匙已不在当前授权列表中") }
            let preference = self.preference(door)
            if preference.transport == .sound { try SoundProtocol.validate(door, timestamp: self.clock()) }
            else { try door.validate(now: self.clock()) }
            if preference.transport == .bluetooth, [6, 7].contains(door.type), let current = self.account {
                if let token = try await self.api.verify(door, account: current), !token.isEmpty { self.account?.token = token; try self.persistAccount() }
            }
            let anchor = self.synchronizedAt, server = self.serverTime
            let clock = { server + Int64(ProcessInfo.processInfo.systemUptime - anchor) }
            if preference.transport == .sound { try await self.sound.open(door, band: preference.band, clock: clock) }
            else { try await self.bluetooth.open(door, clock: clock) }
            self.message = "\(preference.transport == .sound ? "声波" : "蓝牙请求")已发送。请确认门的实际状态。"
    }
    var shortcutAccountTag: String {
        guard !isDemo, let account else { return "" }
        let key = "shortcutAccountTag." + account.mobile
        if let tag = UserDefaults.standard.string(forKey: key) { return tag }
        let tag = UUID().uuidString
        UserDefaults.standard.set(tag, forKey: key)
        return tag
    }
    private func updateShortcutCatalog() {
        guard !isDemo else { return }
        let entries = favorites.map { FavoriteDoorEntity(id: shortcutAccountTag + "|" + $0.id, name: title($0)) }
        FavoriteDoorEntity.save(entries)
    }
    func openFromShortcut(_ identifier: String) async throws {
        guard !isDemo else { throw PocketError.invalid("请退出演示后登录使用快捷指令") }
        guard !busy else { throw PocketError.invalid("正在执行其他操作，请稍后重试") }
        guard account != nil, identifier.hasPrefix(shortcutAccountTag + "|") else { throw PocketError.invalid("请登录创建此快捷指令时的账户") }
        let doorID = String(identifier.dropFirst(shortcutAccountTag.count + 1))
        guard preferences[doorID]?.favorite == true else { throw PocketError.invalid("这把钥匙已取消常用，请重新选择") }
        busy = true
        let task = Task { try await self.openAuthorizedDoor(doorID) }
        shortcutTask = task
        defer { busy = false; opening = nil; shortcutTask = nil }
        do {
            try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        } catch {
            if let service = error as? ServiceError, ["-400", "-300"].contains(service.code) {
                try? SecureStorage.delete("account"); account = nil; doors = []; preferences = [:]; FavoriteDoorEntity.save([]); clearWatchAccount()
            }
            message = error.localizedDescription
            throw error
        }
    }
#if DEBUG && targetEnvironment(simulator)
    func runDemoIsolationChecks() async {
        var checks: [String] = []
        func expect(_ condition: Bool, _ name: String) throws {
            guard condition else { throw PocketError.invalid(name) }
            checks.append(name)
        }
        var result: [String: Any]
        do {
            try expect(account == nil && !busy, "Fresh simulator has no active account")
            let savedAccount = try SecureStorage.read("account")
            let savedCatalog = UserDefaults.standard.data(forKey: "favoriteShortcutCatalog")
            enterDemo()
            try expect(isDemo && doors.count == 2 && favorites.count == 2, "Demo loads two favorite sample doors")
            for door in doors {
                var bleRejected = false, soundRejected = false
                do { try door.validate(now: Int64(Date().timeIntervalSince1970)) } catch { bleRejected = true }
                do { try SoundProtocol.validate(door, timestamp: Int64(Date().timeIntervalSince1970)) } catch { soundRejected = true }
                try expect(bleRejected && soundRejected, "Sample \(door.id) rejected by real protocol validators")
            }
            let sample = doors[0]
            open(sample)
            try expect(!busy && opening == nil && message.contains("未扫描蓝牙"), "Demo open never starts real operation")
            refresh()
            try expect(!busy && message.contains("不会向服务器同步"), "Demo refresh never starts server request")
            sendCode(mobile: "13800000000")
            try expect(!busy && message == "请退出演示后登录", "Demo cannot request SMS")
            login(mobile: "13800000000", code: "123456")
            try expect(!busy && message == "请退出演示后登录", "Demo cannot authenticate a real account")
            var shortcutRejected = false
            do { try await openFromShortcut("demo:forbidden") } catch { shortcutRejected = true }
            try expect(shortcutRejected && !busy, "Demo rejects shortcut execution")
            configure(sample, alias: "演示修改", favorite: false, transport: .sound, band: .low)
            try expect(preference(sample).alias == "演示修改", "Demo configuration remains interactive")
            try expect(UserDefaults.standard.data(forKey: "favoriteShortcutCatalog") == savedCatalog, "Demo does not publish shortcut credentials")
            logout()
            try expect(!isDemo && account == nil && doors.isEmpty, "Exit restores signed-out state")
            try expect(try SecureStorage.read("account") == savedAccount, "Demo does not change persisted account")
            result = ["success": true, "checks": checks]
        } catch { result = ["success": false, "checks": checks, "error": error.localizedDescription] }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("demo-isolation-checks.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
    }
#endif
    func syncToWatch() {
        guard !isDemo, let account, !busy else { message = "请先登录真实账户并等待当前操作完成"; return }
        do {
            WatchBridge.shared.start()
            try WatchBridge.shared.send(try JSONEncoder().encode(WatchTransfer(account: account, preferences: preferences)))
            message = "已提交手表同步。请在配对手表打开钥匙口袋查看；之后开门需手表联网。"
        } catch { message = error.localizedDescription }
    }
    private func clearWatchAccount() {
        if let data = try? JSONEncoder().encode(WatchTransfer(account: nil, preferences: [:])) { try? WatchBridge.shared.send(data) }
    }
    func cancel() { shortcutTask?.cancel(); activeTask?.cancel(); bluetooth.cancel(); sound.cancel() }
    func logout() {
        guard !busy else { return }
        if isDemo { isDemo = false; account = nil; doors = []; preferences = [:]; message = "已退出演示，请登录你的账户"; return }
        do { try SecureStorage.delete("account"); account = nil; doors = []; preferences = [:]; FavoriteDoorEntity.save([]); clearWatchAccount(); serverTime = 0; message = "已退出登录" }
        catch { message = "无法清除登录信息：\(error.localizedDescription)" }
    }
}
