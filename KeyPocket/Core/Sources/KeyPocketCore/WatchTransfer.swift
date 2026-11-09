import Foundation

/// No cached door authorizations are transferred. The watch fetches live grants itself.
public struct WatchTransfer: Codable {
    public var version = 1
    public let revision: String
    public let account: Account?
    public let preferences: [String: DoorPreference]
    public init(account: Account?, preferences: [String: DoorPreference]) {
        revision = UUID().uuidString
        self.account = account
        self.preferences = preferences
    }
}
