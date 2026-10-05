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

    /// Ou vit le jeu : dans le client Steam, dans le dossier Cidre (`cidre dl`),
    /// ou hors Steam (`cidre add`).
    public enum Source: String, Sendable {
        case steam, cidre, local
    }

    /// La cle du jeu pour la CLI : l'appid Steam, ou `local-...` hors Steam.
    public let id: String
    /// `nil` pour un jeu hors Steam.
    public let appid: Int?
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

    /// Un jeu Windows lance par Steam sans le wrapper Cidre ne demarrera pas.
    public var wrapperMissing: Bool {
        platform == .windows && source == .steam && wrapper == false
    }

    enum CodingKeys: String, CodingKey {
        case id, appid, source, wrapper
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
        appid = try c.decodeIfPresent(Int.self, forKey: .appid)
        // Une CLI d'avant les jeux hors Steam ne donne pas `id` : c'est l'appid.
        if let id = try c.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else if let appid {
            id = String(appid)
        } else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "ni id ni appid"))
        }
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
    /// Les options resolues : reglages livres par Cidre + ceux de l'utilisateur.
    public let options: LaunchOptions
    /// Les options que l'utilisateur a lui-meme reglees pour ce jeu.
    public let overridden: Set<LaunchOptions.Key>

    enum CodingKeys: String, CodingKey {
        case savesSynced = "sauvegardes"
        case options
        case overrides = "options_perso"
    }

    public init(from decoder: Decoder) throws {
        game = try Game(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savesSynced = try c.decodeIfPresent(Bool.self, forKey: .savesSynced) ?? false
        options = try c.decodeIfPresent(LaunchOptions.self, forKey: .options) ?? LaunchOptions()
        let overrides = try c.decodeIfPresent([String: OptionValue].self, forKey: .overrides) ?? [:]
        overridden = Set(overrides.keys.compactMap(LaunchOptions.Key.init(rawValue:)))
    }

    /// Une valeur d'option, dont seul le nom de la cle nous interesse ici.
    private struct OptionValue: Decodable {
        init(from decoder: Decoder) throws {}
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
    /// Vrai plein ecran macOS (couvre l'encoche). `nil` : ce Cidre ne connait pas l'option.
    public var fullscreen: Bool?
    /// Game Mode de macOS force pendant le jeu. `nil` : ce Cidre ne connait pas l'option.
    public var gameMode: Bool?
    /// Overlay Steam en jeu (Maj+Tab). `nil` : ce Cidre ne connait pas l'option.
    public var overlay: Bool?
    /// La langue du jeu : `auto` (suivre macOS et Steam) ou un code a deux
    /// lettres. `nil` : ce Cidre ne connait pas l'option.
    public var language: String?

    public init() {}

    /// Les options telles que Cidre les nomme (`tso=true vsync=false ...`), pour
    /// un rapport d'incident.
    public var summary: String {
        var parts = [
            "tso=\(tso)", "vsync=\(vsync)", "hud=\(hud)", "async=\(asyncShaders)",
            "fils_compilation=\(compilerThreads)", "eac_untrusted=\(eacUntrusted)", "luajit=\(luajit)",
        ]
        if let fullscreen { parts.append("plein_ecran=\(fullscreen)") }
        if let gameMode { parts.append("gamemode=\(gameMode)") }
        if let overlay { parts.append("overlay=\(overlay)") }
        if let language { parts.append("langue=\(language)") }
        return parts.joined(separator: " ")
    }

    /// Les noms des options pour la CLI (`cidre set <id> <option> <valeur>`).
    public enum Key: String, CodingKey, CaseIterable, Sendable {
        case tso, vsync, hud, luajit
        case asyncShaders = "async"
        case compilerThreads = "fils_compilation"
        case eacUntrusted = "eac_untrusted"
        case fullscreen = "plein_ecran"
        case gameMode = "gamemode"
        case overlay
        case language = "langue"
    }

    typealias CodingKeys = Key

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
        fullscreen = try c.decodeIfPresent(Bool.self, forKey: .fullscreen)
        gameMode = try c.decodeIfPresent(Bool.self, forKey: .gameMode)
        overlay = try c.decodeIfPresent(Bool.self, forKey: .overlay)
        language = try c.decodeIfPresent(String.self, forKey: .language)
    }
}

/// Les reglages generaux (`cidre options --json`) : ce que suit tout jeu qui n'a
/// pas son propre reglage.
public struct DefaultOptions: Decodable, Sendable {
    public let options: LaunchOptions
    /// Les options que l'utilisateur a changees par rapport a ce que livre Cidre.
    public let overridden: Set<LaunchOptions.Key>

    enum CodingKeys: String, CodingKey {
        case options
        case overrides = "options_perso"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        options = try c.decode(LaunchOptions.self, forKey: .options)
        let overrides = try c.decodeIfPresent([String: Ignored].self, forKey: .overrides) ?? [:]
        overridden = Set(overrides.keys.compactMap(LaunchOptions.Key.init(rawValue:)))
    }

    private struct Ignored: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// Le compte Steam et l'etat de sa session (`cidre session --json`).
public struct SteamSession: Decodable, Equatable, Sendable {
    public let account: String
    /// SteamCMD a une session memorisee : on peut installer et mettre a jour.
    public let connected: Bool

    enum CodingKeys: String, CodingKey {
        case account = "compte"
        case connected = "connecte"
    }
}

/// Un jeu que possede le compte Steam, installe ou non (`cidre library --json`).
public struct OwnedGame: Decodable, Identifiable, Hashable, Sendable {
    public let appid: Int
    public let name: String
    /// Les versions que Steam distribue : "windows", "macos".
    public let platforms: [String]
    public let installed: Bool

    public var id: Int { appid }
    public var hasMac: Bool { platforms.contains("macos") }
    public var hasWindows: Bool { platforms.contains("windows") }

    enum CodingKeys: String, CodingKey {
        case appid
        case name = "nom"
        case platforms = "plateformes"
        case installed = "installe"
    }
}

/// La version installee d'un jeu Steam face a la derniere publiee (`cidre updates --json`).
public struct GameUpdate: Decodable, Equatable, Sendable {
    public let appid: Int
    public let installedBuild: Int
    public let availableBuild: Int
    public let upToDate: Bool

    enum CodingKeys: String, CodingKey {
        case appid
        case installedBuild = "build_installe"
        case availableBuild = "build_disponible"
        case upToDate = "a_jour"
    }
}

/// L'avancement d'un `cidre dl`, lu dans la sortie de SteamCMD.
public struct DownloadProgress: Equatable, Sendable {
    /// De 0 a 1.
    public var fraction: Double
    public var doneBytes: Int64
    public var totalBytes: Int64

    public init(fraction: Double = 0, doneBytes: Int64 = 0, totalBytes: Int64 = 0) {
        self.fraction = fraction
        self.doneBytes = doneBytes
        self.totalBytes = totalBytes
    }

    /// Le dernier avancement que porte un morceau de sortie, s'il y en a un :
    /// ` Update state (0x61) downloading, progress: 37.93 (32564012 / 85850313)`
    public static func last(in output: String) -> DownloadProgress? {
        var found: DownloadProgress?
        for match in output.matches(of: /progress: ([0-9.]+) \((\d+) \/ (\d+)\)/) {
            guard let percent = Double(match.1), let done = Int64(match.2), let total = Int64(match.3),
                  total > 0 else { continue }
            found = DownloadProgress(fraction: min(percent / 100, 1), doneBytes: done, totalBytes: total)
        }
        return found
    }
}
