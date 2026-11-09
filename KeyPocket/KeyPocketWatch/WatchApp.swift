import SwiftUI
import KeyPocketCore
import WatchKit

@main
struct KeyPocketWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchDoorsView().environmentObject(model)
                .tint(Color(red: 0.08, green: 0.65, blue: 0.53))
                .onChange(of: phase) { _, value in if value == .background { model.cancel() } }
        }
    }
}

@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var doors: [DoorKey] = []
    @Published private(set) var preferences: [String: DoorPreference] = [:]
    @Published private(set) var busy = false
    @Published private(set) var message = "请先在 iPhone 钥匙口袋的配置页同步到手表"
    let bluetooth = BluetoothDoorClient()
    private let sound = WatchSoundClient()
    private let api = KeybootAPI()
    private var task: Task<Void, Never>?
    private var revision = ""
    private var generation = UUID()
    var favorites: [DoorKey] { doors.filter { preferences[$0.id]?.favorite == true }.sorted { (preferences[$0.id]?.order ?? 0) < (preferences[$1.id]?.order ?? 0) } }
    init() {
        if let data = try? SecureStorage.read("watchState"), let state = try? JSONDecoder().decode(WatchTransfer.self, from: data) {
            account = state.account; preferences = state.preferences; revision = state.revision
        }
        WatchBridge.shared.onReceive = { [weak self] data in self?.receive(data) }
        WatchBridge.shared.start()
    }
    func title(_ door: DoorKey) -> String {
        let alias = preferences[door.id]?.alias.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? door.title : alias
    }
    func preference(_ door: DoorKey) -> DoorPreference { preferences[door.id] ?? DoorPreference() }
    private func persist() throws {
        // Preserve the received revision so a rejected session is not restored from cached WC context.
        let state = StoredWatchState(revision: revision, account: account, preferences: preferences)
        try SecureStorage.write(try JSONEncoder().encode(state), key: "watchState")
    }
    private func receive(_ data: Data) {
        do {
            let state = try JSONDecoder().decode(WatchTransfer.self, from: data)
            guard state.version == 1, state.revision != revision else { return }
            cancel(); generation = UUID(); revision = state.revision
            account = state.account; preferences = state.preferences; doors = []
            try persist()
            message = account == nil ? "iPhone 已退出账户" : "账户已同步，可不带手机使用。开门需手表联网。"
            if account != nil { refresh() }
        } catch { account = nil; doors = []; message = "无法安全保存同步信息，请重新同步" }
    }
    private struct StoredWatchState: Codable {
        var version = 1
        let revision: String
        let account: Account?
        let preferences: [String: DoorPreference]
    }
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        task = Task {
            defer { busy = false; task = nil }
            do { try await work() }
            catch is CancellationError { message = "已取消" }
            catch {
                if let error = error as? ServiceError, ["-400", "-300"].contains(error.code) { account = nil; doors = []; try? persist() }
                message = (error as NSError).domain == NSURLErrorDomain ? "手表网络请求失败，请连接 Wi-Fi 或蜂窝网络后重试。" : error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }
    private func refreshGrants() async throws -> KeyResponse {
        guard let account else { throw PocketError.invalid("请在 iPhone 上重新同步账户") }
        let current = generation
        let response = try await api.refresh(account)
        try Task.checkCancellation()
        guard current == generation else { throw CancellationError() }
        if let token = response.token, !token.isEmpty { self.account?.token = token }
        doors = response.doors
        try persist()
        return response
    }
    func refresh() {
        run {
            self.message = "正在通过手表网络同步…"
            _ = try await self.refreshGrants()
            self.message = self.favorites.isEmpty ? "暂无常用门，请在 iPhone 配置后重新同步到手表" : "已同步，靠近门禁后点击开门"
        }
    }
    func open(_ selected: DoorKey) {
        run {
            self.message = "检查最新授权…"
            let response = try await self.refreshGrants()
            let anchor = ProcessInfo.processInfo.systemUptime
            guard let door = response.doors.first(where: { $0.id == selected.id }), self.preferences[door.id]?.favorite == true else { throw PocketError.invalid("这把钥匙已撤销或不在常用门中") }
            let pref = self.preference(door)
            if pref.transport == .sound { try SoundProtocol.validate(door, timestamp: response.serverTime) }
            else { try door.validate(now: response.serverTime) }
            if pref.transport == .bluetooth, [6, 7].contains(door.type), let account = self.account {
                if let token = try await self.api.verify(door, account: account), !token.isEmpty { self.account?.token = token; try self.persist() }
            }
            try Task.checkCancellation()
            let clock = { response.serverTime + Int64(ProcessInfo.processInfo.systemUptime - anchor) }
            guard response.serverTime > 0, ProcessInfo.processInfo.systemUptime - anchor < 120 else { throw PocketError.invalid("授权时间过期，请重试") }
            if pref.transport == .sound {
                self.message = "正在从手表扬声器发送…"
                try await self.sound.open(door, band: pref.band, clock: clock)
            } else { try await self.bluetooth.open(door, clock: clock) }
            self.message = "请求已发送，请确认门的实际状态"
            WKInterfaceDevice.current().play(.notification)
        }
    }
    func cancel() { task?.cancel(); bluetooth.cancel(); sound.cancel() }
    func signOut() {
        guard !busy else { return }
        generation = UUID(); account = nil; doors = []; preferences = [:]
        do { try persist(); message = "已移除手表账户" } catch { message = "无法清除手表账户，请重试" }
    }
}

struct WatchDoorsView: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        NavigationStack {
            List {
                if model.account == nil {
                    Section {
                        Image(systemName: "key.horizontal.fill").font(.largeTitle).foregroundStyle(.tint)
                        Text("在 iPhone 配置页点击「同步到 Apple Watch」")
                        Text("同步后可不带手机使用；手表需要 Wi-Fi 或蜂窝网络。").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("常用门") {
                        ForEach(model.favorites) { door in
                            Button { model.open(door) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(model.title(door), systemImage: "door.left.hand.closed")
                                    Text(model.preference(door).transport.title).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }.disabled(model.busy || !door.enabled)
                        }
                        if model.favorites.isEmpty { Text("刷新钥匙，或从 iPhone 同步常用门配置") }
                    }
                    Button("刷新钥匙") { model.refresh() }.disabled(model.busy)
                }
                Section {
                    if model.busy { ProgressView(); Button("取消", role: .cancel) { model.cancel() } }
                    Text(model.busy && model.bluetooth.status != "等待开门" ? model.bluetooth.status + "\n" + model.message : model.message).font(.footnote)
                }
                if model.account != nil {
                    Section { Button("移除手表账户", role: .destructive) { model.signOut() }.disabled(model.busy) }
                }
            }.navigationTitle("钥匙口袋")
                .onReceive(model.bluetooth.objectWillChange) { model.objectWillChange.send() }
                .task { if model.account != nil && model.doors.isEmpty && !model.busy { model.refresh() } }
        }
    }
}
