import AppIntents
import Foundation

struct FavoriteDoorEntity: AppEntity, Codable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "常用门"
    static var defaultQuery = FavoriteDoorQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static func load() -> [Self] {
        guard let data = UserDefaults.standard.data(forKey: "favoriteShortcutCatalog") else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
    static func save(_ entries: [Self]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "favoriteShortcutCatalog")
        }
        KeyPocketShortcuts.updateAppShortcutParameters()
    }
}
struct FavoriteDoorQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoriteDoorEntity] {
        FavoriteDoorEntity.load().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [FavoriteDoorEntity] { FavoriteDoorEntity.load() }
}
struct OpenFavoriteDoorIntent: AppIntent {
    static var title: LocalizedStringResource = "打开常用门"
    static var description = IntentDescription("使用当前账户的最新授权，通过已配置的蓝牙或声波方式打开指定常用门。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "常用门") var door: FavoriteDoorEntity
    static var parameterSummary: some ParameterSummary { Summary("打开 \(\.$door)") }
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.openFromShortcut(door.id)
        return .result(dialog: "开门请求已发送，请确认门的实际状态。")
    }
}
struct KeyPocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFavoriteDoorIntent(), phrases: ["使用\(.applicationName)打开常用门"], shortTitle: "打开常用门", systemImageName: "key.fill")
    }
}
