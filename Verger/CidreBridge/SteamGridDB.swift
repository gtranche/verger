import Foundation

/// SteamGridDB (steamgriddb.com) : une base communautaire d'illustrations de
/// jeux, y compris pour ceux qui ne sont pas sur Steam. C'est elle que les
/// extensions du Steam Deck utilisent pour habiller les jeux non-Steam.
/// Son API demande une cle personnelle, gratuite, que l'utilisateur cree sur
/// son compte et colle dans les reglages.
public struct SteamGridDB: Sendable {
    public struct Match: Decodable, Identifiable, Hashable, Sendable {
        public let id: Int
        public let name: String
    }

    /// Une jaquette au format portrait.
    public struct Grid: Decodable, Identifiable, Equatable, Sendable {
        public let id: Int
        public let url: URL
        public let thumb: URL
    }

    public enum Failure: Error, LocalizedError, Sendable, Equatable {
        case missingKey
        case refusedKey
        case server(Int)

        public var errorDescription: String? {
            switch self {
            case .missingKey: L10n.string("Il faut une clé SteamGridDB (gratuite) pour chercher des jaquettes.")
            case .refusedKey: L10n.string("SteamGridDB refuse cette clé : vérifie-la dans les réglages.")
            case let .server(status): L10n.format("SteamGridDB a répondu %lld.", status)
            }
        }
    }

    public static let keyPage = URL(string: "https://www.steamgriddb.com/profile/preferences/api")!

    let key: String
    let base: URL

    public init(key: String, base: URL = URL(string: "https://www.steamgriddb.com/api/v2")!) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.base = base
    }

    /// Les jeux dont le nom ressemble a `term`.
    public func search(_ term: String) async throws -> [Match] {
        try await get("search/autocomplete/" + (term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term))
    }

    /// Les jaquettes portrait (600x900) d'un jeu de SteamGridDB.
    public func grids(forGame id: Int) async throws -> [Grid] {
        try await get("grids/game/\(id)", query: "dimensions=600x900")
    }

    /// Les jaquettes portrait d'un jeu Steam, par son appid.
    public func grids(forSteamApp appid: Int) async throws -> [Grid] {
        try await get("grids/steam/\(appid)", query: "dimensions=600x900")
    }

    func request(_ path: String, query: String? = nil) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(_ path: String, query: String? = nil) async throws -> [T] {
        guard !key.isEmpty else { throw Failure.missingKey }
        let (data, response) = try await URLSession.shared.data(for: request(path, query: query))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 401, status != 403 else { throw Failure.refusedKey }
        // 404 : SteamGridDB ne connait pas ce jeu
        guard status != 404 else { return [] }
        guard status == 200 else { throw Failure.server(status) }
        return try Self.decode(data)
    }

    static func decode<T: Decodable>(_ data: Data) throws -> [T] {
        try JSONDecoder().decode(Envelope<T>.self, from: data).data ?? []
    }
}

/// La forme de toutes les reponses de l'API : `{"success": true, "data": [...]}`.
private struct Envelope<Item: Decodable>: Decodable {
    let success: Bool
    let data: [Item]?
}
