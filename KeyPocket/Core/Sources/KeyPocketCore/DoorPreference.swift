import Foundation

public struct DoorPreference: Codable {
    public var alias = ""
    public var favorite = false
    public var order = 0
    public var transport: DoorTransport = .bluetooth
    public var band: SoundBand = .standard
    public init(alias: String = "", favorite: Bool = false, order: Int = 0) { self.alias = alias; self.favorite = favorite; self.order = order }
    private enum CodingKeys: String, CodingKey { case alias, favorite, order, transport, band }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alias = try values.decodeIfPresent(String.self, forKey: .alias) ?? ""
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
        transport = try values.decodeIfPresent(DoorTransport.self, forKey: .transport) ?? .bluetooth
        band = try values.decodeIfPresent(SoundBand.self, forKey: .band) ?? .standard
    }
}
