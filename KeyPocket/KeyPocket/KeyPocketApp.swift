import SwiftUI
import AppIntents
import KeyPocketCore

@main
struct KeyPocketApp: App {
    init() { WatchBridge.shared.start() }
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .tint(Color(red: 0.08, green: 0.47, blue: 0.40))
                .onChange(of: scenePhase) { phase in if phase == .background { model.cancel() } }
                .onAppear {
#if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("--demo-selftest") {
                        Task { await model.runDemoIsolationChecks() }
                    } else if ProcessInfo.processInfo.arguments.contains("--demo") { model.enterDemo() }
#endif
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab = 0
    private var screenshotSettings: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--settings")
#else
        false
#endif
    }
    var body: some View {
        Group {
            if model.account == nil { LoginView() }
            else if screenshotSettings, model.isDemo, let door = model.doors.last {
                NavigationStack { DoorSettingsView(door: door) }
            }
            else {
                TabView(selection: $selectedTab) {
                    DoorsView().tabItem { Label("开门", systemImage: "door.left.hand.open") }.tag(0)
                    ConfigurationView().tabItem { Label("配置", systemImage: "slider.horizontal.3") }.tag(1)
                }
                .onAppear {
#if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("--configuration") { selectedTab = 1 }
#endif
                }
            }
        }
    }
}

struct DemoNoticeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            Label("功能演示 · 示例钥匙", systemImage: "sparkles").font(.caption.bold())
            Spacer()
            Button("退出演示") { model.logout() }.font(.caption)
        }.foregroundStyle(.tint).padding(.vertical, 4)
    }
}

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var mobile = ""
    @State private var code = ""
    @State private var agreed = false
    @State private var showingPrivacy = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "key.horizontal.fill").font(.system(size: 44)).foregroundStyle(.tint)
                        Text("钥匙口袋").font(.largeTitle.bold())
                        Text("常用的门，一触即达。\n使用你已有的钥匙宝账户。").foregroundStyle(.secondary)
                    }.padding(.vertical, 24)
                }.listRowBackground(Color.clear)
                Section("账户登录") {
                    TextField("手机号", text: $mobile).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .accessibilityLabel("手机号")
                    HStack {
                        TextField("短信验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(ceil(model.codeAvailableAt.timeIntervalSince(context.date))))
                            Button(seconds > 0 ? "\(seconds)秒后重发" : "获取验证码") { model.sendCode(mobile: mobile.trimmingCharacters(in: .whitespacesAndNewlines)) }
                                .disabled(model.busy || !agreed || seconds > 0 || mobile.count != 11)
                        }
                    }
                    Toggle("我已阅读数据说明及原服务条款", isOn: $agreed).font(.footnote)
                    HStack {
                        Link("服务协议", destination: URL(string: "http://oss.app.keyboot.com/img/ad/Agreement.html")!)
                        Spacer()
                        Button("数据与隐私说明") { showingPrivacy = true }
                    }.font(.footnote)
                }
                Section {
                    Button { model.login(mobile: mobile.trimmingCharacters(in: .whitespacesAndNewlines), code: code.trimmingCharacters(in: .whitespacesAndNewlines)) } label: {
                        HStack { Spacer(); if model.busy { ProgressView() }; Text("登录并同步钥匙").bold(); Spacer() }.padding(.vertical, 6)
                    }.disabled(model.busy || !agreed || mobile.count != 11 || code.isEmpty)
                } footer: {
                    Text("独立兼容客户端。仅使用你已有授权的门禁，账户令牌保存在此 iPhone 的钥匙串中。")
                }
                Section {
                    Button { model.enterDemo() } label: { Label("查看功能演示", systemImage: "play.rectangle") }
                } footer: { Text("无需登录，使用示例钥匙了解功能。演示不会连接真实门禁。") }
                Section { Text(model.message).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
            }
            .sheet(isPresented: $showingPrivacy) { PrivacyInformationView() }
        }
    }
}

struct PrivacyInformationView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("账户与授权") { Text("真实登录时，手机号、验证码、应用生成的设备标识及设备型号会发送给原钥匙宝服务，用于登录、同步钥匙和检查权限。开门时会按钥匙类型向原服务检查授权。") }
                Section("此 iPhone 上的数据") { Text("登录令牌保存在系统钥匙串；别名、常用顺序和传输设置保存在本机。退出登录会移除本机账户令牌，不会注销原服务账户或删除物业授权。") }
                Section("Apple Watch 同步") { Text("仅在你点击同步到 Apple Watch 时，账户令牌和常用门配置会通过系统配对连接发送到你的手表。令牌保存在手表钥匙串中，手表可自行向原服务同步授权。手机退出登录后的清除请求需在手表下次连接时送达；你也可以直接在手表移除账户。") }
                Section("蓝牙与声音") { Text("蓝牙仅用于寻找并连接你选择的门禁。声波通过手机扬声器输出。本 App 不录音、不上传声音，也不收集 GPS 位置、通讯录或照片。") }
                Section("演示模式") { Text("演示使用内置示例钥匙，不请求短信、不连接服务器、不扫描蓝牙，也不发送声波。示例不能用于真实开门。") }
                Section("第三方服务与控制") {
                    Text("钥匙口袋是独立兼容客户端。原服务负责账户、钥匙授权及其服务器数据；这些处理适用原服务的隐私政策。本 App 不包含广告或第三方统计 SDK。")
                    Link("查看原服务隐私政策", destination: URL(string: "http://oss.app.keyboot.com/img/ad/privacy.html")!)
                    Text("你可以在系统设置中撤销蓝牙权限，或退出登录、删除 App 以停止使用。原服务账户的查询、修改或注销，请联系原服务或物业。")
                }
            }.navigationTitle("数据与隐私")
                .toolbar { Button("完成") { dismiss() } }
        }
    }
}

struct DoorsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View { DoorListContent(bluetooth: model.bluetooth, sound: model.sound) }
}

struct DoorListContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var bluetooth: BluetoothDoorClient
    @ObservedObject var sound: SoundDoorClient
    var body: some View {
        NavigationStack {
            List {
                if model.isDemo { Section { DemoNoticeView() }.listRowBackground(Color.green.opacity(0.08)) }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("回家，只需轻轻一点。").font(.title2.bold())
                        Text("靠近门禁后，选择要打开的门。").foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear)
                Section("常用门") {
                    if model.favorites.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("还没有常用门", systemImage: "star")
                            Text("到「配置」页选择门禁，并为它们设置容易辨认的名称。").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 14)
                    }
                    ForEach(model.favorites) { door in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Image(systemName: "door.left.hand.closed").font(.title2).foregroundStyle(.tint).frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.title(door)).font(.headline)
                                    if model.title(door) != door.title { Text(door.title).font(.caption).foregroundStyle(.secondary) }
                                    Text(model.preference(door).transport.title).font(.caption).foregroundStyle(.tint)
                                    Text("有效至 " + Date(timeIntervalSince1970: Double(door.expires)).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button { model.open(door) } label: {
                                HStack { Spacer(); if model.opening == door.id { ProgressView() }; Text(model.opening == door.id ? "正在开门…" : "打开这扇门").bold(); Spacer() }.padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent).disabled(model.busy || !(model.preference(door).transport == .sound ? door.supportsSound : door.supportsBluetooth) || !door.enabled)
                            if !door.supportsBluetooth { Text("此钥匙类型暂不支持，请使用官方 App。").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 10)
                    }
                }
                Section {
                    Text(model.opening == nil ? model.message : (model.doors.first(where: { $0.id == model.opening }).map { model.preference($0).transport == .sound ? sound.status : bluetooth.status } ?? model.message)).font(.subheadline).accessibilityAddTraits(.updatesFrequently)
                    if model.busy { Button("取消当前操作", role: .cancel) { model.cancel() } }
                } footer: { Text("请求发送完成不代表门已解锁，请确认门的实际状态。") }
            }
            .navigationTitle("我的门")
            .toolbar { Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy).accessibilityLabel("刷新钥匙") }
            .refreshable { model.refresh() }
            .task { if model.doors.isEmpty { model.refresh() } }
        }
    }
}

struct ConfigurationView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                if model.isDemo { Section { DemoNoticeView() }.listRowBackground(Color.green.opacity(0.08)) }
                Section("Apple Watch") {
                    Button("同步到 Apple Watch") { model.syncToWatch() }.disabled(model.busy || model.isDemo)
                    Text("将账户和常用门配置同步到配对手表。手表之后可自行联网检查授权并开门；请仅同步到你自己的手表。手机退出登录后，清除请求会在手表下次连接时送达；也可直接在手表移除账户。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("系统快捷入口") {
                    ShortcutsLink()
                    Text("添加「打开常用门」动作并选择钥匙，可用于操作按钮或辅助触控菜单。执行时会打开本 App，并验证钥匙权限。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("常用门顺序") {
                    if model.favorites.isEmpty { Text("从下方选择常用门").foregroundStyle(.secondary) }
                    ForEach(model.favorites) { door in Text(model.title(door)) }
                        .onMove { model.moveFavorites(from: $0, to: $1) }
                }
                Section("账户已授权的门") {
                    ForEach(model.doors) { door in
                        NavigationLink { DoorSettingsView(door: door) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(model.title(door)); if model.preference(door).favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) } }
                                Text(door.supportsBluetooth ? (door.supportsSound ? "蓝牙 / 声波 · 点击配置" : "蓝牙开门 · 点击配置") : "暂不支持此类型").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text(model.account?.mobile ?? "")
                    Button(model.isDemo ? "了解钥匙同步" : "同步授权钥匙") { model.refresh() }.disabled(model.busy)
                    Button(model.isDemo ? "退出演示" : "退出登录", role: .destructive) { model.logout() }.disabled(model.busy)
                } header: { Text("账户") } footer: { Text("配置只改变此 iPhone 上的显示名称和常用顺序。门禁权限由物业及原服务管理。") }
            }.navigationTitle("门禁配置").toolbar { EditButton() }
        }
    }
}

struct DoorSettingsView: View {
    @EnvironmentObject var model: AppModel
    let door: DoorKey
    var body: some View {
        Form {
            if model.isDemo { Section { DemoNoticeView() }.listRowBackground(Color.green.opacity(0.08)) }
            Section("在此 iPhone 上") {
                TextField("例如：小区南门", text: Binding(get: { model.preference(door).alias }, set: { model.configure(door, alias: $0) }))
                Toggle("显示在常用门", isOn: Binding(get: { model.preference(door).favorite }, set: { model.configure(door, favorite: $0) }))
            }
            Section {
                Picker("开门方式", selection: Binding(get: { model.preference(door).transport }, set: { model.configure(door, transport: $0) })) {
                    Text(DoorTransport.bluetooth.title).tag(DoorTransport.bluetooth)
                    if door.supportsSound { Text(DoorTransport.sound.title).tag(DoorTransport.sound) }
                }
                if model.preference(door).transport == .sound {
                    Picker("声波频段", selection: Binding(get: { model.preference(door).band }, set: { model.configure(door, band: $0) })) {
                        ForEach(SoundBand.allCases, id: \.self) { band in Text(band.title).tag(band) }
                    }
                }
            } header: { Text("开门方式") } footer: {
                Text(door.supportsSound ? "声波固定从手机扬声器播放，会短暂中断音乐。请靠近接收器并调高媒体音量；若标准频段不稳定，可改用低频兼容或高频。" : "这类钥匙暂不支持声波。")
            }
            Section("授权信息") {
                LabeledContent("原始名称", value: door.title)
                LabeledContent("钥匙编号", value: String(door.keyID))
                LabeledContent("有效期", value: Date(timeIntervalSince1970: Double(door.expires)).formatted(date: .abbreviated, time: .shortened))
                LabeledContent("开门方式", value: door.supportsBluetooth ? model.preference(door).transport.title : "需官方 App")
            }
        }.navigationTitle("配置这扇门")
    }
}
