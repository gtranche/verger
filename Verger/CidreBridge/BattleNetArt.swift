import Foundation

/// Les images d'un jeu Battle.net (id `bnet-<code>`), prises la ou le client de
/// Blizzard les garde : son cache (AppData/Local/Battle.net/Cache, dans son
/// prefixe Wine), ou chaque image est rangee sous son hash md5
/// (Cache/ab/cd/abcd...) et decrite par des index JSON
/// (`{"files":{"default":{"osi#OSI_X2_KEY_ART":{"hash":...,"name":...}}}}`).
/// La « key art » est un portrait 600x800 (3:4) ; a defaut, le fond
/// d'installation, en paysage. Rien sur le reseau, aucune cle d'API.
public enum BattleNetArt {
    public struct Found: Equatable, Sendable {
        public let file: URL
        /// `true` : portrait (key art) ; `false` : paysage (fond d'installation).
        public let isPortrait: Bool
    }

    /// Le produit des images quand il differe du code Cidre (bnet-fen : fenris).
    static let products = ["fen": "fenris"]
    /// Le meme jeu sur Steam, pour reprendre ses jaquettes si le cache du
    /// client n'a rien (Diablo IV : 2344520). Diablo II: Resurrected n'y est pas.
    public static let steamAppIDs = ["fen": 2_344_520]

    /// « osi » pour bnet-osi ; `nil` pour un autre jeu.
    public static func code(of id: String) -> String? {
        guard id.hasPrefix("bnet-"), id.count > 5 else { return nil }
        return String(id.dropFirst(5)).lowercased()
    }

    public static func product(of code: String) -> String { products[code] ?? code }

    /// Le prefixe Wine d'un jeu installe dedans (…/pfx/drive_c/…) ; `nil` s'il
    /// est ailleurs (un disque externe lie au prefixe).
    public static func prefix(ofGamePath path: String) -> String? {
        guard let range = path.range(of: "/drive_c/") else { return nil }
        return String(path[..<range.lowerBound])
    }

    /// Les dossiers Cache du client, un par utilisateur du prefixe.
    static func cacheDirectories(prefix: String) -> [URL] {
        let users = URL(fileURLWithPath: prefix, isDirectory: true).appendingPathComponent("drive_c/users")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? []
        return names.sorted().map { users.appendingPathComponent($0).appendingPathComponent("AppData/Local/Battle.net/Cache", isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// L'image du jeu dans le cache du client : sa key art, sinon son fond
    /// d'installation. Lit le disque (quelques centaines de petits fichiers) :
    /// hors du fil principal.
    public static func find(code: String, prefix: String) -> Found? {
        for cache in cacheDirectories(prefix: prefix) {
            if let found = find(product: product(of: code), cache: cache) { return found }
        }
        return nil
    }

    static func find(product: String, cache: URL) -> Found? {
        // les index, du plus recent au plus ancien : le client garde les
        // anciens, dont les images ont pu partir du cache
        var portraits: [(Date, URL)] = []
        var landscapes: [(Date, URL)] = []
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: keys) else { return nil }
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, size > 0, size < 4_000_000,
                  let data = try? Data(contentsOf: file), data.first == UInt8(ascii: "{"),
                  let index = try? JSONDecoder().decode(Index.self, from: data),
                  let entries = index.files["default"] else { continue }
            let date = values.contentModificationDate ?? .distantPast
            for (key, entry) in entries {
                let parts = key.split(separator: "#", maxSplits: 1)
                guard parts.count == 2, parts[0] == product, let hash = entry.hash, let image = imageFile(hash: hash, cache: cache) else { continue }
                if parts[1].contains("KEY_ART") {
                    portraits.append((date, image))
                } else if parts[1].hasSuffix("INSTALL_BACKGROUND") {
                    landscapes.append((date, image))
                }
            }
        }
        if let best = portraits.max(by: { $0.0 < $1.0 }) { return Found(file: best.1, isPortrait: true) }
        if let best = landscapes.max(by: { $0.0 < $1.0 }) { return Found(file: best.1, isPortrait: false) }
        return nil
    }

    /// Cache/ab/cd/abcd… s'il y est.
    static func imageFile(hash: String, cache: URL) -> URL? {
        let hash = hash.lowercased()
        guard hash.count == 32, hash.allSatisfy(\.isHexDigit) else { return nil }
        let file = cache.appendingPathComponent(String(hash.prefix(2)))
            .appendingPathComponent(String(hash.dropFirst(2).prefix(2)))
            .appendingPathComponent(hash)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private struct Index: Decodable {
        let files: [String: [String: Entry]]
    }

    private struct Entry: Decodable {
        let hash: String?
    }
}
