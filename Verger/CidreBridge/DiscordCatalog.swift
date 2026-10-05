import Foundation

/// Les jeux que Discord connait, avec l'identifiant sous lequel il les affiche.
///
/// Discord publie cette liste (c'est elle qui lui sert a reconnaitre un jeu qui
/// tourne sur Windows). On y cherche un jeu par son appid Steam, sinon par son
/// nom ; l'identifiant trouve sert ensuite a l'annoncer (`DiscordPresence`),
/// avec le nom et l'icone que Discord lui donne lui-meme.
public struct DiscordCatalog: Codable, Equatable, Sendable {
    public static let source = URL(string: "https://discord.com/api/v9/applications/detectable")!

    /// appid Steam -> identifiant Discord
    var bySteamApp: [String: String]
    /// nom normalise (et alias) -> identifiant Discord
    var byName: [String: String]

    public var count: Int { Set(byName.values).union(bySteamApp.values).count }

    /// L'identifiant Discord d'un jeu, s'il le connait.
    public func applicationID(name: String, steamAppID: Int?) -> String? {
        if let steamAppID, let id = bySteamApp[String(steamAppID)] { return id }
        return byName[Self.normalize(name)]
    }

    /// Les noms se comparent sans casse, sans ponctuation et sans marques deposees.
    static func normalize(_ name: String) -> String {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .replacingOccurrences(of: "©", with: "")
        return cleaned.split { !($0.isLetter || $0.isNumber) }.joined(separator: " ")
    }

    /// Reduit la liste de Discord (13 Mo) a ce qu'on y cherche.
    static func parse(_ data: Data) throws -> DiscordCatalog {
        struct Application: Decodable {
            struct SKU: Decodable {
                let distributor: String?
                let id: String?
            }
            let id: String
            let name: String
            let aliases: [String]?
            let third_party_skus: [SKU]?
        }
        let applications = try JSONDecoder().decode([Application].self, from: data)
        var bySteamApp: [String: String] = [:], byName: [String: String] = [:]
        // Deux passes : les noms d'abord, les alias ensuite, pour qu'un alias
        // ne prenne jamais la place du nom d'un autre jeu.
        for app in applications {
            for sku in app.third_party_skus ?? [] where sku.distributor == "steam" {
                if let appid = sku.id, bySteamApp[appid] == nil { bySteamApp[appid] = app.id }
            }
            let key = normalize(app.name)
            if !key.isEmpty, byName[key] == nil { byName[key] = app.id }
        }
        for app in applications {
            for alias in app.aliases ?? [] {
                let key = normalize(alias)
                if !key.isEmpty, byName[key] == nil { byName[key] = app.id }
            }
        }
        return DiscordCatalog(bySteamApp: bySteamApp, byName: byName)
    }

    /// Le catalogue, depuis le cache s'il est assez recent, sinon depuis Discord
    /// (et mis en cache). Hors ligne, un cache meme ancien fait l'affaire.
    public static func load(
        cache: URL, maxAge: TimeInterval = 7 * 24 * 3600, source: URL = DiscordCatalog.source
    ) async -> DiscordCatalog? {
        let fm = FileManager.default
        let cached = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode(DiscordCatalog.self, from: $0) }
        let age = (try? fm.attributesOfItem(atPath: cache.path)[.modificationDate] as? Date)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        if let cached, age < maxAge { return cached }

        let fetched: Data?
        if source.isFileURL {
            fetched = try? Data(contentsOf: source)
        } else if let (data, response) = try? await URLSession.shared.data(from: source),
                  (response as? HTTPURLResponse)?.statusCode == 200 {
            fetched = data
        } else {
            fetched = nil
        }
        guard let fetched, let catalog = try? parse(fetched) else { return cached }
        try? fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(catalog).write(to: cache, options: .atomic)
        return catalog
    }
}
