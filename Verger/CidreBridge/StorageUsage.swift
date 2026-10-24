import Foundation

/// L'occupation d'un disque de jeux, pour sa barre : ce que prennent les jeux
/// Cidre, le reste de ce qui est occupe, et le libre. `nil` pour un disque
/// debranche (Cidre ne donne alors ni libre ni total).
public struct DiskUsage: Hashable, Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    /// Les jeux Cidre de cet emplacement (au plus l'occupe).
    public let gamesBytes: Int64

    public init(totalBytes: Int64, freeBytes: Int64, gamesBytes: Int64) {
        self.totalBytes = max(totalBytes, 0)
        self.freeBytes = min(max(freeBytes, 0), self.totalBytes)
        self.gamesBytes = min(max(gamesBytes, 0), self.totalBytes - self.freeBytes)
    }

    /// D'apres `cidre emplacements`. `availableBytes` : la place que macOS
    /// laisse a l'utilisateur (`volumeAvailableCapacityForImportantUsage`,
    /// purgeable compris), plus juste que le `df` de Cidre sur APFS ; `gamesBytes` :
    /// la taille des jeux mesuree par Verger quand elle depasse celle de Cidre.
    public init?(location: StorageLocation, availableBytes: Int64? = nil, gamesBytes: Int64? = nil) {
        guard location.online, let total = location.totalBytes, total > 0,
              let free = availableBytes.flatMap({ $0 > 0 ? $0 : nil }) ?? location.freeBytes else { return nil }
        self.init(totalBytes: total, freeBytes: free, gamesBytes: max(location.gamesBytes, gamesBytes ?? 0))
    }

    public var usedBytes: Int64 { totalBytes - freeBytes }
    /// Occupe par autre chose que les jeux Cidre.
    public var otherBytes: Int64 { usedBytes - gamesBytes }

    public var gamesFraction: Double { fraction(gamesBytes) }
    public var otherFraction: Double { fraction(otherBytes) }
    public var freeFraction: Double { fraction(freeBytes) }

    private func fraction(_ bytes: Int64) -> Double {
        totalBytes > 0 ? Double(bytes) / Double(totalBytes) : 0
    }

    /// « 820 Go utilisés sur 1 To · 74 Go libres ».
    public var summary: String {
        L10n.format("%@ utilisés sur %@ · %@ libres", L10n.bytes(usedBytes), L10n.bytes(totalBytes), L10n.bytes(freeBytes))
    }

    /// Moins de 10 % de libre : la barre le dit.
    public var isNearlyFull: Bool { freeFraction < 0.1 }
}

extension StorageLocation {
    /// Le jeu est-il installe sur cet emplacement ? Un jeu Cidre dit le sien
    /// (`emplacement`) ; un jeu du client Steam ou hors Steam n'en a pas : on
    /// le range d'apres son chemin, sur le disque externe dont il est (par son
    /// volume), sinon sur ce Mac.
    public func holds(_ game: Game, among locations: [StorageLocation]) -> Bool {
        guard game.installed else { return false }
        if let id = game.location { return id == self.id }
        if let volume = Self.gameVolumeName(of: game.path) {
            return locations.first { $0.volume == volume }?.id == id
        }
        return isMain
    }

    /// Le volume du dossier d'un jeu, au bout de son lien s'il en est un : le
    /// dossier d'un jeu Battle.net, dans le prefixe du client, peut pointer
    /// sur un disque externe (meme debranche : le lien se lit sans sa cible).
    public static func gameVolumeName(of path: String) -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return volumeName(of: path)
        }
        let resolved = target.hasPrefix("/") ? target : (path as NSString).deletingLastPathComponent + "/" + target
        return volumeName(of: resolved)
    }

    /// « SSD » pour /Volumes/SSD/... ; `nil` sur le disque du Mac.
    public static func volumeName(of path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return String(parts[1])
    }
}

/// La file des deplacements demandes depuis la page Stockage : un seul tourne
/// a la fois (deux copies sur le meme disque se gênent), les autres attendent
/// et s'annulent tant qu'ils n'ont pas commence.
public struct MoveQueue: Sendable {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let gameID: String
        public let name: String
        public let sizeBytes: Int64
        public let to: String
        public var id: String { gameID }

        public init(gameID: String, name: String, sizeBytes: Int64, to: String) {
            self.gameID = gameID
            self.name = name
            self.sizeBytes = sizeBytes
            self.to = to
        }
    }

    public private(set) var pending: [Entry] = []

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }

    /// Ajoute un deplacement ; un jeu deja en attente change seulement de destination.
    public mutating func enqueue(_ entry: Entry) {
        if let index = pending.firstIndex(where: { $0.gameID == entry.gameID }) {
            pending[index] = entry
        } else {
            pending.append(entry)
        }
    }

    /// Le prochain a lancer, retire de la file.
    public mutating func next() -> Entry? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    public mutating func cancel(_ gameID: String) {
        pending.removeAll { $0.gameID == gameID }
    }

    public mutating func cancelAll() {
        pending.removeAll()
    }

    public func contains(_ gameID: String) -> Bool {
        pending.contains { $0.gameID == gameID }
    }

    /// Ce qui attend d'aller sur un emplacement : de quoi avertir s'il n'y tient pas.
    public func pendingBytes(to location: String) -> Int64 {
        pending.filter { $0.to == location }.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// La taille sur disque d'un dossier de jeu, quand Cidre ne la donne pas (jeu
/// hors Steam, manifeste sans `SizeOnDisk`) : mesuree en arriere-plan, gardee
/// en cache (une semaine) pour ne pas reparcourir le disque a chaque ouverture.
public enum GameSizes {
    private static let key = "taillesJeux"
    private static let lifetime: TimeInterval = 7 * 24 * 3600

    /// La taille en cache pour ce chemin, si elle est encore fraiche.
    public static func cached(_ path: String, defaults: UserDefaults = .standard, now: Date = Date()) -> Int64? {
        guard let entry = (defaults.dictionary(forKey: key) as? [String: [Double]])?[path], entry.count == 2,
              now.timeIntervalSince1970 - entry[1] < lifetime else { return nil }
        return Int64(entry[0])
    }

    public static func store(_ bytes: Int64, for path: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        var all = (defaults.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
        all[path] = [Double(bytes), now.timeIntervalSince1970]
        defaults.set(all, forKey: key)
    }

    /// Les octets occupes par un dossier (taille allouee, comme le Finder) ;
    /// `nil` s'il n'existe pas.
    public static func measure(_ path: String) -> Int64? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// La place libre que macOS laisse aux usages importants (purgeable
    /// compris), comme le Finder ; `nil` si le volume ne la donne pas.
    public static func importantAvailableCapacity(at path: String) -> Int64? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let value = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, value > 0 else { return nil }
        return value
    }
}
