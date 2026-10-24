import Foundation

/// Un volume monte sur lequel on pourrait mettre des jeux : un disque externe,
/// une carte, un second volume du Mac. Ni le disque systeme, ni un volume cache
/// (Time Machine), reseau ou en lecture seule.
public struct MountedVolume: Hashable, Sendable {
    public let name: String
    /// La racine du volume, /Volumes/<nom>.
    public let path: String
    public let isInternal: Bool
    public let freeBytes: Int64?
    public let totalBytes: Int64?

    public init(name: String, path: String, isInternal: Bool = false, freeBytes: Int64? = nil, totalBytes: Int64? = nil) {
        self.name = name
        self.path = path
        self.isInternal = isInternal
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }

    /// Les volumes montes en ce moment. Lit le disque : hors du fil principal.
    public static func current() -> [MountedVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRootFileSystemKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
            .volumeIsReadOnlyKey, .volumeIsInternalKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard url.path.hasPrefix("/Volumes/"), let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true, values.volumeIsLocal != false,
                  values.volumeIsBrowsable != false, values.volumeIsReadOnly != true else { return nil }
            return MountedVolume(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                isInternal: values.volumeIsInternal == true,
                freeBytes: values.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil },
                totalBytes: values.volumeTotalCapacity.map(Int64.init))
        }
    }
}

/// Un disque ou installer et deplacer des jeux, a la maniere d'une console :
/// ce Mac, puis chaque disque externe branche, puis ceux qui sont debranches.
/// Derriere, un emplacement Cidre (`cidre emplacements`) ; un disque branche
/// que Cidre ne connait pas encore n'en a pas : le choisir le lui ajoute (un
/// dossier « Jeux Cidre » a sa racine).
public struct GameDisk: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case thisMac, internalVolume, external }

    /// L'id de l'emplacement Cidre, ou « volume:<chemin> » s'il n'en a pas encore.
    public let id: String
    public let name: String
    public let kind: Kind
    public let location: StorageLocation?
    /// Le volume monte, pour l'ajouter a Cidre ; `nil` sur ce Mac ou debranche.
    public let volume: MountedVolume?

    public var online: Bool { location?.online ?? true }
    public var isNew: Bool { location == nil }
    /// On peut y installer ou y deplacer un jeu.
    public var acceptsGames: Bool { location?.acceptsGames ?? true }
    public var freeBytes: Int64? { location?.freeBytes ?? volume?.freeBytes }
    public var isDefault: Bool { location?.isDefault == true }

    public var symbol: String {
        if !online { return "externaldrive.badge.xmark" }
        return kind == .external ? "externaldrive" : "internaldrive"
    }

    /// « SSK SSD — 350 Go libres », « Disque X — débranché ».
    public var label: String {
        if !online { return L10n.format("%@ — débranché", name) }
        guard let free = freeBytes else { return name }
        return L10n.format("%@ — %@ libres", name, L10n.bytes(free))
    }

    /// Les disques, d'apres les emplacements de Cidre et les volumes montes.
    /// Un emplacement dans un dossier de ce Mac (ajoute a la main) n'est pas un
    /// disque : il reste dans les reglages avances. Plusieurs emplacements sur
    /// un meme volume : celui par defaut, sinon le premier.
    public static func list(locations: [StorageLocation], mounted: [MountedVolume]) -> [GameDisk] {
        var disks: [GameDisk] = []
        if let main = locations.first(where: \.isMain) {
            disks.append(GameDisk(id: main.id, name: main.name, kind: .thisMac, location: main, volume: nil))
        }
        var byVolume: [String: StorageLocation] = [:]
        for location in locations where !location.isMain {
            guard let volume = location.volume else { continue }
            if let known = byVolume[volume], known.isDefault || !location.isDefault { continue }
            byVolume[volume] = location
        }
        var online: [GameDisk] = []
        for volume in mounted {
            let kind: Kind = volume.isInternal ? .internalVolume : .external
            if let location = byVolume.removeValue(forKey: volume.name) {
                online.append(GameDisk(id: location.id, name: location.name, kind: kind, location: location, volume: volume))
            } else {
                online.append(GameDisk(id: "volume:" + volume.path, name: volume.name, kind: kind, location: nil, volume: volume))
            }
        }
        // les emplacements dont le volume n'est pas dans la liste : debranches,
        // ou montes mais ecartes (lecture seule)
        let others = byVolume.values.map {
            GameDisk(id: $0.id, name: $0.name, kind: .external, location: $0, volume: nil)
        }
        let byName: (GameDisk, GameDisk) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return disks + online.sorted(by: byName) + others.filter(\.online).sorted(by: byName) + others.filter { !$0.online }.sorted(by: byName)
    }

    /// Le disque d'un jeu Cidre (par son emplacement), sinon d'apres son chemin.
    public static func of(_ game: Game, among disks: [GameDisk]) -> GameDisk? {
        if let id = game.location, let disk = disks.first(where: { $0.location?.id == id }) { return disk }
        if let volume = StorageLocation.gameVolumeName(of: game.path) {
            return disks.first { $0.location?.volume == volume || $0.volume?.name == volume }
        }
        return disks.first { $0.kind == .thisMac }
    }

    /// Le nom du disque debranche ou est un jeu hors ligne (« SSK SSD ») :
    /// celui de son emplacement Cidre, sinon le volume de son chemin (un jeu
    /// Battle.net) ; `nil` si on ne sait pas.
    public static func unpluggedName(of game: Game, among locations: [StorageLocation]) -> String? {
        if let id = game.location, let location = locations.first(where: { $0.id == id }) { return location.name }
        return StorageLocation.gameVolumeName(of: game.path)
    }

    /// Les jeux hors ligne, par disque debranche (dans l'ordre des noms) ;
    /// « » pour ceux dont on ne connait pas le disque.
    public static func unplugged(_ games: [Game], among locations: [StorageLocation]) -> [(disk: String, games: [Game])] {
        let offline = games.filter { !$0.online }
        let groups = Dictionary(grouping: offline) { unpluggedName(of: $0, among: locations) ?? "" }
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { ($0, groups[$0]!) }
    }
}
