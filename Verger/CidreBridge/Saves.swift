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
    public let local: Side?
    public let backup: Side?
    /// Copies de precaution gardees avant chaque ecrasement.
    public let history: Int

    enum CodingKeys: String, CodingKey {
        case id
        case configured = "configure"
        case state = "etat"
        case folder = "dossier"
        case backupFolder = "copie"
        case onICloud = "icloud"
        case local
        case backup = "sauvegarde"
        case history = "historique"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        configured = try c.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        state = State(rawValue: try c.decodeIfPresent(String.self, forKey: .state) ?? "") ?? .unknown
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        backupFolder = try c.decodeIfPresent(String.self, forKey: .backupFolder)
        onICloud = try c.decodeIfPresent(Bool.self, forKey: .onICloud) ?? false
        local = try c.decodeIfPresent(Side.self, forKey: .local)
        backup = try c.decodeIfPresent(Side.self, forKey: .backup)
        history = try c.decodeIfPresent(Int.self, forKey: .history) ?? 0
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
