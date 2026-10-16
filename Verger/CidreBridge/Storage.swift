import Foundation

/// Un emplacement ou vivent des jeux Cidre (`cidre emplacements --json`) : le
/// principal, sur ce Mac, ou un disque externe ajoute par l'utilisateur.
public struct StorageLocation: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    /// « Ce Mac », le nom du volume, ou le dossier.
    public let name: String
    public let path: String
    /// Le volume (sous /Volumes) ; `nil` sur le disque du Mac.
    public let volume: String?
    /// `false` : le disque est debranche ; ses jeux sont « hors ligne ».
    public let online: Bool
    /// Les nouveaux jeux y vont.
    public let isDefault: Bool
    /// L'emplacement principal, sur ce Mac : il ne se retire pas.
    public let isMain: Bool
    public let removable: Bool
    /// apfs, exfat, msdos, hfs... ; `nil` debranche.
    public let fileSystem: String?
    public let freeBytes: Int64?
    public let totalBytes: Int64?
    /// `false` : en lecture seule (NTFS) ; `nil` debranche.
    public let writable: Bool?
    public let gameCount: Int
    public let gamesBytes: Int64
    /// Une phrase de Cidre pour le joueur (exFAT, debranche...).
    public let remark: String?

    /// On peut y installer ou y deplacer un jeu.
    public var acceptsGames: Bool { online && writable != false }

    /// Ce qu'on dit au joueur de cet emplacement (debranche, exFAT, FAT32,
    /// lecture seule, reseau), dans la langue de l'interface ; la remarque de
    /// Cidre pour un cas que ce Verger ne connait pas.
    public var explanation: String? {
        if !online {
            return gameCount > 1
                ? L10n.format("Débranché : branche « %@ » pour retrouver ses %@ jeux. Ils ne sont ni désinstallés ni perdus.", name, String(gameCount))
                : L10n.format("Débranché : branche « %@ » pour retrouver ses jeux. Ils ne sont ni désinstallés ni perdus.", name)
        }
        if writable == false {
            return L10n.string("En lecture seule (NTFS ?) : Cidre ne peut rien y installer ni y déplacer.")
        }
        switch fileSystem {
        case "exfat": return L10n.string("exFAT : lisible aussi par Windows, mais sans droits Unix ni clones APFS ; APFS convient mieux à un disque réservé au Mac.")
        case "msdos": return L10n.string("FAT32 : aucun fichier de plus de 4 Go ; beaucoup de jeux n'y tiennent pas. Reformate le disque en APFS ou exFAT.")
        case "smbfs", "nfs", "afpfs", "webdav": return L10n.string("Volume réseau : les jeux y chargent lentement.")
        case "apfs", "hfs", nil: return nil
        default: return remark
        }
    }

    /// « 3 jeux · 12 Go », « 1 jeu · 2 Go », « aucun jeu ».
    public var gamesSummary: String {
        switch gameCount {
        case 0: L10n.string("aucun jeu")
        case 1: L10n.format("1 jeu · %@", L10n.bytes(gamesBytes))
        default: L10n.format("%@ jeux · %@", String(gameCount), L10n.bytes(gamesBytes))
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, volume, remark = "remarque"
        case name = "nom"
        case path = "chemin"
        case online = "en_ligne"
        case isDefault = "defaut"
        case isMain = "principal"
        case removable = "amovible"
        case fileSystem = "systeme_fichiers"
        case freeBytes = "libre"
        case totalBytes = "total"
        case writable = "inscriptible"
        case gameCount = "jeux"
        case gamesBytes = "taille_jeux"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        volume = try c.decodeIfPresent(String.self, forKey: .volume)
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isMain = try c.decodeIfPresent(Bool.self, forKey: .isMain) ?? false
        removable = try c.decodeIfPresent(Bool.self, forKey: .removable) ?? false
        fileSystem = try c.decodeIfPresent(String.self, forKey: .fileSystem)
        freeBytes = try c.decodeIfPresent(Int64.self, forKey: .freeBytes)
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes)
        writable = try c.decodeIfPresent(Bool.self, forKey: .writable)
        gameCount = try c.decodeIfPresent(Int.self, forKey: .gameCount) ?? 0
        gamesBytes = try c.decodeIfPresent(Int64.self, forKey: .gamesBytes) ?? 0
        remark = try c.decodeIfPresent(String.self, forKey: .remark)
    }
}

/// Un emplacement Cidre trouve sur un disque branche, pas encore ajoute (retire,
/// ou venu d'un autre Mac) : l'ajouter fait revenir ses jeux.
public struct DetectedLocation: Decodable, Identifiable, Hashable, Sendable {
    public let path: String
    public let locationID: String
    public let volume: String?
    public let gameCount: Int

    public var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path = "chemin"
        case locationID = "id"
        case volume
        case gameCount = "jeux"
    }
}

/// `cidre emplacements --json`.
public struct StorageLocations: Decodable, Sendable {
    public let locations: [StorageLocation]
    public let detected: [DetectedLocation]

    enum CodingKeys: String, CodingKey {
        case locations = "emplacements"
        case detected = "detectes"
    }

    public init(locations: [StorageLocation] = [], detected: [DetectedLocation] = []) {
        self.locations = locations
        self.detected = detected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locations = try c.decode([StorageLocation].self, forKey: .locations)
        detected = try c.decodeIfPresent([DetectedLocation].self, forKey: .detected) ?? []
    }
}

/// Le deplacement d'un jeu vers un autre emplacement (`cidre move`) : en
/// cours, ou reste inacheve (interrompu, echoue). Le meme objet dans
/// `cidre list --json` (`"deplacement"`) et les evenements de `cidre move --json`.
public struct MoveStatus: Decodable, Hashable, Sendable {
    public enum State: String, Sendable {
        case running = "en_cours"
        /// Arrete en route (Verger ferme, Annuler) : l'original est intact, un
        /// nouveau `cidre move` reprend ou il en etait.
        case interrupted = "interrompu"
        /// Copie impossible (place, disque debranche, verification) : idem.
        case failed = "echoue"
        /// Refuse avant de commencer (jeu en cours, place...) : rien n'a bouge.
        case refused = "refuse"
        case done = "fait"
        /// Abandonne (`--annuler`) : la copie entamee est effacee.
        case cancelled = "annule"
        case unknown = "inconnu"
    }

    public enum Phase: String, Sendable {
        case preparation, copie, verification, bascule, suppression
    }

    public let state: State
    public let phase: Phase?
    /// Les ids des emplacements de depart et d'arrivee.
    public let from: String?
    public let to: String?
    public let progress: DownloadProgress?
    /// place, debranche, en_jeu, verification, copie, liens, existe...
    public let reason: String?
    public let message: String?

    public var isRunning: Bool { state == .running }
    /// A reprendre ou a abandonner : l'original est intact.
    public var isUnfinished: Bool { state == .interrupted || state == .failed }

    enum CodingKeys: String, CodingKey {
        case state = "etat"
        case phase
        case from = "de"
        case to = "vers"
        case percent = "avancement"
        case doneBytes = "octets"
        case totalBytes = "total"
        case reason = "raison"
        case message
    }

    public init(state: State, phase: Phase? = nil, from: String? = nil, to: String? = nil,
                progress: DownloadProgress? = nil, reason: String? = nil, message: String? = nil) {
        self.state = state
        self.phase = phase
        self.from = from
        self.to = to
        self.progress = progress
        self.reason = reason
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = State(rawValue: try c.decode(String.self, forKey: .state)) ?? .unknown
        phase = try c.decodeIfPresent(String.self, forKey: .phase).flatMap(Phase.init(rawValue:))
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        if let percent = try c.decodeIfPresent(Double.self, forKey: .percent) {
            progress = DownloadProgress(
                fraction: min(max(percent / 100, 0), 1),
                doneBytes: try c.decodeIfPresent(Int64.self, forKey: .doneBytes) ?? 0,
                totalBytes: try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0)
        } else if let total = try c.decodeIfPresent(Int64.self, forKey: .totalBytes), total > 0 {
            progress = DownloadProgress(fraction: 0, doneBytes: 0, totalBytes: total)
        } else {
            progress = nil
        }
    }

    /// Ce qui se passe, en quelques mots, pour la barre d'avancement.
    public var phaseLabel: String {
        switch phase {
        case .preparation: L10n.string("Préparation…")
        case .verification: L10n.string("Vérification de la copie…")
        case .bascule, .suppression: L10n.string("Finalisation…")
        case .copie, nil: L10n.string("Copie…")
        }
    }

    /// Ce qu'on dit au joueur d'un deplacement inacheve : pourquoi il s'est
    /// arrete, et que l'original est intact. `nil` s'il n'y a rien a dire.
    public var explanation: String? {
        guard isUnfinished else { return nil }
        switch reason {
        case "interrompu":
            return L10n.string("Le déplacement a été arrêté avant la fin : le jeu est toujours ici, intact. Il peut reprendre où il en était.")
        case "debranche":
            return L10n.string("Un disque a été débranché pendant le déplacement : le jeu est toujours ici, intact. Rebranche-le pour reprendre où il en était.")
        case "place":
            return L10n.string("La place a manqué sur le disque d'arrivée : le jeu est toujours ici, intact. Libère de la place pour reprendre, ou abandonne.")
        case "verification":
            return L10n.string("La copie ne correspondait pas à l'original : rien n'a été effacé. Reprendre refait la copie de ce qui diffère.")
        default:
            return L10n.string("Le déplacement de ce jeu s'est arrêté avant la fin : il est toujours ici, intact.")
                + (message.map { "\n\($0)" } ?? "")
        }
    }

    /// Un evenement de `cidre move --json` ; `nil` pour toute autre ligne.
    public static func parse(line: String) -> MoveStatus? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("{"), let data = line.data(using: .utf8),
              let kind = try? JSONDecoder().decode(Kind.self, from: data), kind.name == "deplacement" else { return nil }
        return try? JSONDecoder().decode(MoveStatus.self, from: data)
    }

    private struct Kind: Decodable {
        let name: String
        enum CodingKeys: String, CodingKey { case name = "evenement" }
    }
}
