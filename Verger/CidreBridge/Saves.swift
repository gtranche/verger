import Foundation

/// Ou en est la synchro des sauvegardes d'un jeu (`cidre saves <id> --json`).
///
/// Cidre copie les sauvegardes d'un jeu Windows vers un dossier iCloud : il
/// restaure ce qui y est plus recent au lancement, et sauvegarde a la sortie.
public struct SaveStatus: Decodable, Equatable, Sendable {
    public enum State: String, Sendable {
        case upToDate = "a_jour"
        /// Des fichiers ont change sur ce Mac depuis la derniere sauvegarde.
        case needsBackup = "a_sauvegarder"
        /// La copie porte des fichiers plus recents (une partie jouee ailleurs).
        case needsRestore = "a_restaurer"
        case diverged = "divergent"
        case neverBackedUp = "jamais_sauvegarde"
        /// Steam synchronise ce jeu lui-meme (dossier macOS lie) : Cidre ne copie rien.
        case steam = "steam"
        /// Rien d'un cote ni de l'autre : le jeu n'a pas encore sauvegarde.
        case empty = "vide"
        case unknown
    }

    /// Un cote de la synchro : ce Mac, ou la copie.
    public struct Side: Decodable, Equatable, Sendable {
        public let files: Int
        public let bytes: Int64
        /// La date du fichier le plus recent.
        public let modified: Date?

        enum CodingKeys: String, CodingKey {
            case files = "fichiers"
            case bytes = "octets"
            case modified = "modifie"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            files = try c.decodeIfPresent(Int.self, forKey: .files) ?? 0
            bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
            let epoch = try c.decodeIfPresent(Double.self, forKey: .modified) ?? 0
            modified = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
        }
    }

    public let id: String
    /// Cidre sait ou ce jeu range ses sauvegardes. Sinon, rien d'autre n'est renseigne.
    public let configured: Bool
    public let state: State
    /// Le dossier des sauvegardes sur ce Mac.
    public let folder: String?
    /// Le dossier de la copie.
    public let backupFolder: String?
    /// La copie est dans iCloud Drive (sinon elle reste sur ce Mac).
    public let onICloud: Bool
    /// Comment ce jeu est synchronise : "steam_api" (API Remote Storage, par le
    /// pont), "steam_macos" (dossier macOS declare a Steam Cloud, lie), "copie"
    /// (copie Cidre, locale ou iCloud), "aucune" (dossier inconnu). Absent avec
    /// un Cidre d'avant la 1.5.9.
    public let sync: String?
    /// La meme chose en une phrase, ecrite par Cidre.
    public let syncDetail: String?
    public let local: Side?
    public let backup: Side?
    /// Copies de precaution gardees avant chaque ecrasement.
    public let history: Int
    /// Ce que `cidre import` a ramene de la bouteille d'ou vient le jeu
    /// (`"reprise"`). `nil` : le jeu ne vient pas d'une bouteille, ou Cidre plus ancien.
    public let imported: SavesImport?

    /// Steam synchronise ce jeu lui-meme (par l'API ou par le dossier macOS lie).
    public var syncedBySteam: Bool { sync == "steam_api" || sync == "steam_macos" }

    enum CodingKeys: String, CodingKey {
        case id
        case configured = "configure"
        case state = "etat"
        case folder = "dossier"
        case backupFolder = "copie"
        case onICloud = "icloud"
        case sync = "synchro"
        case syncDetail = "synchro_detail"
        case local
        case backup = "sauvegarde"
        case history = "historique"
        case imported = "reprise"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        configured = try c.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        state = State(rawValue: try c.decodeIfPresent(String.self, forKey: .state) ?? "") ?? .unknown
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        backupFolder = try c.decodeIfPresent(String.self, forKey: .backupFolder)
        onICloud = try c.decodeIfPresent(Bool.self, forKey: .onICloud) ?? false
        sync = try c.decodeIfPresent(String.self, forKey: .sync)
        syncDetail = try c.decodeIfPresent(String.self, forKey: .syncDetail)
        local = try c.decodeIfPresent(Side.self, forKey: .local)
        backup = try c.decodeIfPresent(Side.self, forKey: .backup)
        history = try c.decodeIfPresent(Int.self, forKey: .history) ?? 0
        imported = try c.decodeIfPresent(SavesImport.self, forKey: .imported)
    }
}

/// Les sauvegardes qu'un jeu repris d'une bouteille CrossOver, Whisky ou Heroic
/// y avait laissees, et ce que Cidre en a ramene : `"reprise_sauvegardes"` de
/// `cidre import --json`, `"reprise"` de `cidre saves --json`.
public struct SavesImport: Decodable, Equatable, Sendable {
    public enum State: String, Sendable {
        /// Des fichiers ont ete ramenes (`files`, dont `replaced`).
        case copied = "copie"
        /// Rien a ramener : identiques, ou plus recents sur ce Mac (`kept`).
        case upToDate = "a_jour"
        /// Steam Cloud les detient (API de Steam) : rien n'est copie.
        case steam
        /// Le jeu les range dans son propre dossier : elles sont venues avec lui.
        case withGame = "avec_le_jeu"
        /// La bouteille n'en a pas.
        case none = "absentes"
        /// Cidre ne sait pas ou ce jeu les range.
        case notFound = "introuvable"
        /// Pas ramenees (disque C: de Cidre absent, bouteille disparue) : `message` dit pourquoi.
        case failed = "erreur"
        case unknown
    }

    public let state: State
    /// Fichiers ecrits sur ce Mac.
    public let files: Int
    /// Parmi eux, ceux qui ont remplace une version plus ancienne (gardee dans l'historique).
    public let replaced: Int
    /// Fichiers plus recents sur ce Mac, laisses tels quels.
    public let kept: Int
    /// L'outil de la bouteille : "crossover", "whisky", "heroic".
    public let origin: String?
    public let bottle: String?
    /// Le dossier de la bouteille, et celui ou les fichiers sont arrives.
    public let from: String?
    public let to: String?
    /// La phrase de Cidre, en francais.
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case state = "etat"
        case files = "fichiers"
        case replaced = "remplaces"
        case kept = "gardes"
        case origin = "origine"
        case bottle = "bouteille"
        case from = "depuis"
        case to = "vers"
        case message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = State(rawValue: try c.decodeIfPresent(String.self, forKey: .state) ?? "") ?? .unknown
        files = try c.decodeIfPresent(Int.self, forKey: .files) ?? 0
        replaced = try c.decodeIfPresent(Int.self, forKey: .replaced) ?? 0
        kept = try c.decodeIfPresent(Int.self, forKey: .kept) ?? 0
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        bottle = try c.decodeIfPresent(String.self, forKey: .bottle)
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }

    /// Ce qu'il faut en dire au joueur, en une ligne, apres « Reprendre ».
    public func notice(game: String) -> String {
        switch state {
        case .copied:
            L10n.format("%@ : %lld fichier(s) de sauvegarde ramené(s) de la bouteille « %@ ».", game, files, bottle ?? "")
        case .upToDate:
            L10n.format("%@ : rien à ramener, les sauvegardes de ce Mac sont identiques à celles de la bouteille, ou plus récentes.", game)
        case .steam:
            L10n.format("%@ : Steam Cloud synchronise déjà ses sauvegardes, rien n'a été copié.", game)
        case .withGame:
            L10n.format("%@ : ses sauvegardes sont dans le dossier du jeu, elles sont venues avec lui.", game)
        case .none:
            L10n.format("%@ : aucune sauvegarde de ce jeu dans la bouteille « %@ ».", game, bottle ?? "")
        case .notFound:
            L10n.format("%@ : sauvegardes non trouvées dans la bouteille « %@ » (Cidre ne sait pas où ce jeu les range).", game, bottle ?? "")
        case .failed, .unknown:
            L10n.format("%@ : ses sauvegardes n'ont pas été ramenées de la bouteille. %@", game, message ?? "")
        }
    }
}

/// Ce que rend `cidre import <appid> --json` : la fiche du jeu repris, et ce
/// qu'il est advenu de ses sauvegardes (`nil` avec un Cidre plus ancien).
public struct ImportResult: Decodable, Sendable {
    public let saves: SavesImport?

    enum CodingKeys: String, CodingKey {
        case saves = "reprise_sauvegardes"
    }

    public init(saves: SavesImport? = nil) {
        self.saves = saves
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        saves = try? c.decodeIfPresent(SavesImport.self, forKey: .saves)
    }
}

extension CidreCLI {
    public enum SyncDirection: String, Sendable {
        /// Copier vers iCloud ce qui a change sur ce Mac.
        case backup
        /// Reprendre de la copie ce qui y est plus recent.
        case restore
    }

    /// `cidre saves <id> --json`
    public func saves(id: String) async throws -> SaveStatus {
        try await json(["saves", id, "--json"])
    }

    /// `cidre sync <id> backup|restore`. Rien n'est ecrase sans copie : Cidre
    /// garde l'ancienne version dans l'historique.
    public func sync(id: String, _ direction: SyncDirection) async throws {
        _ = try await checked(["sync", id, direction.rawValue])
    }

    /// `cidre saves set <id> <dossier> --json` : dire ou le jeu range ses sauvegardes.
    public func setSavesFolder(id: String, _ folder: URL) async throws -> SaveStatus {
        try await json(["saves", "set", id, folder.path, "--json"])
    }

    /// `cidre saves unset <id> --json` : revenir a ce que Cidre sait de lui-meme.
    public func resetSavesFolder(id: String) async throws -> SaveStatus {
        try await json(["saves", "unset", id, "--json"])
    }
}
