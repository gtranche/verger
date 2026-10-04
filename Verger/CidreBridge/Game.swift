import Foundation

/// Un jeu tel que le decrit `cidre list --json`.
public struct Game: Decodable, Identifiable, Hashable, Sendable {
    public enum Platform: String, Sendable {
        case macos, windows, absent, unknown = "inconnu"
    }

    /// Qui lance le jeu : Steam en natif, ou la pile Cidre.
    public enum Launch: String, Sendable {
        case native = "natif", cidre
    }

    /// Ou vit le jeu : dans le client Steam, ou dans le dossier Cidre (`cidre dl`).
    public enum Source: String, Sendable {
        case steam, cidre
    }

    public let appid: Int
    public let name: String
    public let platform: Platform
    public let launch: Launch
    public let source: Source
    public let installed: Bool
    /// Wrapper Cidre pose dans Steam ; `nil` quand le jeu n'est pas lance par Steam.
    public let wrapper: Bool?
    public let path: String
    public let sizeBytes: Int64
    public let lastPlayed: Date?

    public var id: Int { appid }

    /// Un jeu Windows lance par Steam sans le wrapper Cidre ne demarrera pas.
    public var wrapperMissing: Bool {
        platform == .windows && source == .steam && wrapper == false
    }

    enum CodingKeys: String, CodingKey {
        case appid, source, wrapper
        case name = "nom"
        case platform = "plateforme"
        case launch = "lancement"
        case installed = "installe"
        case path = "chemin"
        case sizeBytes = "taille"
        case lastPlayed = "dernier_lancement"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appid = try c.decode(Int.self, forKey: .appid)
        name = try c.decode(String.self, forKey: .name)
        // Une valeur inconnue (CLI plus recente que Verger) ne doit pas faire
        // tomber toute la bibliotheque : on retombe sur une valeur neutre.
        platform = Platform(rawValue: try c.decode(String.self, forKey: .platform)) ?? .unknown
        launch = Launch(rawValue: try c.decode(String.self, forKey: .launch)) ?? .cidre
        source = Source(rawValue: try c.decode(String.self, forKey: .source)) ?? .steam
        installed = try c.decode(Bool.self, forKey: .installed)
        wrapper = try c.decodeIfPresent(Bool.self, forKey: .wrapper)
        path = try c.decode(String.self, forKey: .path)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        // 0 = jamais lance (Steam n'ecrit pas de date)
        let epoch = try c.decodeIfPresent(Double.self, forKey: .lastPlayed) ?? 0
        lastPlayed = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }
}

/// La fiche d'un jeu, `cidre info <appid> --json` : le jeu + ses options actives.
public struct GameInfo: Decodable, Sendable {
    public let game: Game
    /// Le jeu a une ligne dans saves.conf (sauvegardes synchronisees vers iCloud).
    public let savesSynced: Bool
    public let options: LaunchOptions

    enum CodingKeys: String, CodingKey {
        case savesSynced = "sauvegardes"
        case options
    }

    public init(from decoder: Decoder) throws {
        game = try Game(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savesSynced = try c.decodeIfPresent(Bool.self, forKey: .savesSynced) ?? false
        options = try c.decodeIfPresent(LaunchOptions.self, forKey: .options) ?? LaunchOptions()
    }
}

/// Options de lancement resolues par Cidre (profils.toml : livre + utilisateur).
/// Les valeurs par defaut sont celles de la section `[defaut]` livree.
public struct LaunchOptions: Decodable, Equatable, Sendable {
    /// Emulation de l'ordre memoire x86 par FEX. `false` = perf CPU, risque de course.
    public var tso = true
    public var vsync = true
    public var hud = false
    /// Compilation des shaders en fond (DXVK async).
    public var asyncShaders = false
    /// Fils compilateurs DXVK ; 0 = defaut DXVK.
    public var compilerThreads = 0
    public var eacUntrusted = false
    public var luajit = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case tso, vsync, hud, luajit
        case asyncShaders = "async"
        case compilerThreads = "fils_compilation"
        case eacUntrusted = "eac_untrusted"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LaunchOptions()
        tso = try c.decodeIfPresent(Bool.self, forKey: .tso) ?? d.tso
        vsync = try c.decodeIfPresent(Bool.self, forKey: .vsync) ?? d.vsync
        hud = try c.decodeIfPresent(Bool.self, forKey: .hud) ?? d.hud
        asyncShaders = try c.decodeIfPresent(Bool.self, forKey: .asyncShaders) ?? d.asyncShaders
        compilerThreads = try c.decodeIfPresent(Int.self, forKey: .compilerThreads) ?? d.compilerThreads
        eacUntrusted = try c.decodeIfPresent(Bool.self, forKey: .eacUntrusted) ?? d.eacUntrusted
        luajit = try c.decodeIfPresent(Bool.self, forKey: .luajit) ?? d.luajit
    }
}
