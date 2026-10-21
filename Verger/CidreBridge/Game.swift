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
    /// hors Steam (`cidre add`), ou installe par le client Battle.net (id
    /// `bnet-<code>`, sans appid : `cidre play` le lance par le client).
    public enum Source: String, Sendable {
        case steam, cidre, local, battlenet
    }

    /// La cle du jeu pour la CLI : l'appid Steam, `local-...` hors Steam, `bnet-...` Battle.net.
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
    /// L'emplacement d'un jeu Cidre (`cidre emplacements`) ; `nil` ailleurs, ou
    /// Cidre <= 1.5.11.
    public let location: String?
    /// `false` : son disque est debranche. Le jeu reste installe (ni perdu, ni
    /// desinstalle) mais ne se lance pas ; il revient quand on rebranche.
    public let online: Bool
    /// Son deplacement vers un autre emplacement, en cours ou inacheve.
    public let move: MoveStatus?
    /// La version macOS installee n'existe qu'en 32 bits : macOS ne la lance
    /// plus (depuis Catalina, et Rosetta 2 ne traduit pas le 32 bits). Cidre
    /// installe la version Windows (`cidre dl`). `false` aussi pour un Cidre
    /// d'avant ce champ.
    public let mac32Bit: Bool

    /// Une version macOS 32 bits du client Steam : elle ne se lance pas, il
    /// faut la version Windows.
    public var needsWindowsVersion: Bool { mac32Bit && platform == .macos }

    /// Ce qu'on dit d'un jeu dont la version macOS n'existe qu'en 32 bits.
    public static var mac32BitNotice: String {
        L10n.string("Version Mac 32 bits, inutilisable sur ce Mac : Cidre installe la version Windows.")
    }

    /// Installe, branche, et pas en plein deplacement : « Jouer » est possible.
    public var playable: Bool { installed && online && move?.isRunning != true && !needsWindowsVersion }

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
        case location = "emplacement"
        case online = "en_ligne"
        case move = "deplacement"
        case mac32Bit = "mac_32bits"
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
        // (une source inconnue : hors Steam, sans action Steam ni dossier Cidre)
        source = Source(rawValue: try c.decode(String.self, forKey: .source)) ?? .local
        installed = try c.decode(Bool.self, forKey: .installed)
        wrapper = try c.decodeIfPresent(Bool.self, forKey: .wrapper)
        path = try c.decode(String.self, forKey: .path)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        // 0 = jamais lance (Steam n'ecrit pas de date)
        let epoch = try c.decodeIfPresent(Double.self, forKey: .lastPlayed) ?? 0
        lastPlayed = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
        location = try c.decodeIfPresent(String.self, forKey: .location)
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? true
        move = try? c.decodeIfPresent(MoveStatus.self, forKey: .move)
        mac32Bit = (try? c.decodeIfPresent(Bool.self, forKey: .mac32Bit)) == true
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
    /// Ou en est la mise a jour du jeu (`"maj"`), d'apres ce que Cidre sait deja.
    /// `nil` : jeu que Cidre ne met pas a jour lui-meme, ou Cidre <= 1.5.9.
    public let update: UpdateStatus?
    /// Ce que la base de profils dit de la compatibilite du jeu, sur ce Mac et
    /// par famille de Mac. `nil` : pas de fiche, ou une fiche qui n'en dit rien.
    public let compatibility: GameCompatibility?
    /// Les shaders du jeu sur ce Mac. `nil` : jeu macOS, ou Cidre <= 1.5.11.
    public let shaders: ShaderCacheStatus?

    enum CodingKeys: String, CodingKey {
        case savesSynced = "sauvegardes"
        case options
        case overrides = "options_perso"
        case update = "maj"
        case profile = "fiche"
        case shaders
    }

    public init(from decoder: Decoder) throws {
        game = try Game(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savesSynced = try c.decodeIfPresent(Bool.self, forKey: .savesSynced) ?? false
        options = try c.decodeIfPresent(LaunchOptions.self, forKey: .options) ?? LaunchOptions()
        let overrides = try c.decodeIfPresent([String: OptionValue].self, forKey: .overrides) ?? [:]
        overridden = Set(overrides.keys.compactMap(LaunchOptions.Key.init(rawValue:)))
        update = try c.decodeIfPresent(UpdateStatus.self, forKey: .update)
        // une fiche illisible ne doit pas cacher le reste du jeu
        compatibility = (try? c.decodeIfPresent(GameCompatibility.self, forKey: .profile)).flatMap { $0.isEmpty ? nil : $0 }
        // (un etat illisible ne doit pas cacher le reste du jeu)
        shaders = (try? c.decodeIfPresent(ShaderCacheStatus.self, forKey: .shaders)) ?? nil
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
    /// Relache les barrieres GPU KosmicKrisp vers les vraies stages : les passes
    /// se recouvrent, gain en scene chargee. `nil` : ce Cidre ne connait pas l'option.
    public var narrowBarriers: Bool?
    /// Vrai D3D12 via vkd3d-proton arm64ec (sinon d3d12 builtin de Wine, qui
    /// retombe en D3D11/DXVK). `nil` : ce Cidre ne connait pas l'option.
    public var dx12: Bool?
    /// Rendu Direct3D 11 : `dxvk` (DXVK -> Vulkan -> Metal) ou `dxmt` (DXMT,
    /// D3D11 -> Metal en un saut ; l'overlay Steam est alors coupe). `nil` : ce
    /// Cidre ne connait pas l'option.
    public var d3d11: String?
    /// MetalFX spatial x2 sur la sortie (DXMT seulement). `nil` : ce Cidre ne
    /// connait pas l'option.
    public var metalfx: Bool?
    /// La langue du jeu : `auto` (suivre macOS et Steam) ou un code a deux
    /// lettres. `nil` : ce Cidre ne connait pas l'option.
    public var language: String?
    /// Mettre le jeu a jour avant de le lancer quand Steam publie un build plus
    /// recent (jeu du dossier Cidre). `nil` : ce Cidre ne sait pas le faire --
    /// ni l'option, ni `cidre play --json`.
    public var updateBeforeLaunch: Bool?

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
        if let narrowBarriers { parts.append("narrow_barriers=\(narrowBarriers)") }
        if let dx12 { parts.append("dx12=\(dx12)") }
        if let d3d11 { parts.append("d3d11=\(d3d11)") }
        if let metalfx { parts.append("metalfx=\(metalfx)") }
        if let language { parts.append("langue=\(language)") }
        if let updateBeforeLaunch { parts.append("maj_avant_lancement=\(updateBeforeLaunch)") }
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
        case narrowBarriers = "narrow_barriers"
        case dx12
        case d3d11
        case metalfx
        case language = "langue"
        case updateBeforeLaunch = "maj_avant_lancement"
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
        narrowBarriers = try c.decodeIfPresent(Bool.self, forKey: .narrowBarriers)
        dx12 = try c.decodeIfPresent(Bool.self, forKey: .dx12)
        d3d11 = try c.decodeIfPresent(String.self, forKey: .d3d11)
        metalfx = try c.decodeIfPresent(Bool.self, forKey: .metalfx)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        updateBeforeLaunch = try c.decodeIfPresent(Bool.self, forKey: .updateBeforeLaunch)
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
    /// "bouteille" : deja installe par CrossOver, Whisky ou Heroic, que
    /// `cidre import` reprend (clone, bouteille intacte). Absent sinon.
    public let source: String?
    /// L'outil qui l'a installe ("crossover", "whisky", "heroic") et le nom de
    /// sa bouteille.
    public let origin: String?
    public let bottle: String?
    public let path: String?
    public let sizeBytes: Int64?
    /// Sa version macOS n'existe qu'en 32 bits (`"mac_32bits": true`) : macOS ne
    /// la lance plus. Pour Verger, un jeu Windows seulement.
    public let mac32BitOnly: Bool?

    public var id: Int { appid }
    public var inBottle: Bool { source == "bouteille" }
    public var isMac32Bit: Bool { mac32BitOnly == true && platforms.contains("macos") }
    /// Une version macOS qui tourne sur ce Mac : pas une version 32 bits.
    public var hasMac: Bool { platforms.contains("macos") && !isMac32Bit }
    public var hasWindows: Bool { platforms.contains("windows") }

    enum CodingKeys: String, CodingKey {
        case appid
        case name = "nom"
        case platforms = "plateformes"
        case installed = "installe"
        case source
        case origin = "origine"
        case bottle = "bouteille"
        case path = "chemin"
        case sizeBytes = "taille"
        case mac32BitOnly = "mac_32bits"
    }
}

/// La version installee d'un jeu Steam face a la derniere publiee (`cidre updates --json`).
public struct GameUpdate: Decodable, Equatable, Sendable {
    public let appid: Int
    public let installedBuild: Int
    public let availableBuild: Int
    public let upToDate: Bool
    /// Qui met le jeu a jour : `cidre` (jeu du dossier Cidre) ou `steam` (le
    /// client Steam). `nil` : Cidre <= 1.5.9.
    public let source: String?
    /// Ou en est la mise a jour (jeu du dossier Cidre). `nil` : Cidre <= 1.5.9.
    public let status: UpdateStatus?

    /// Un build plus recent est publie. Les builds de Steam ne font que
    /// croitre : un build installe en avance sur le build « publie » trahit une
    /// fiche en retard (cache), pas un jeu perime -- un Cidre <= 1.5.9 le
    /// donnait pourtant « pas a jour » jusqu'a une demi-heure apres un `cidre dl`.
    public var needsUpdate: Bool { !upToDate && availableBuild > installedBuild }

    /// La pastille « Mise a jour » de la carte : pas pour une mise a jour deja
    /// tentee sans effet (Steam ne donne pas ce build a ce compte) -- il n'y a
    /// rien a faire, la fiche du jeu l'explique.
    public var showsBadge: Bool { needsUpdate && status?.reason != .noEffect }

    enum CodingKeys: String, CodingKey {
        case appid, source
        case installedBuild = "build_installe"
        case availableBuild = "build_disponible"
        case upToDate = "a_jour"
        case state = "etat"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appid = try c.decode(Int.self, forKey: .appid)
        installedBuild = try c.decode(Int.self, forKey: .installedBuild)
        availableBuild = try c.decode(Int.self, forKey: .availableBuild)
        upToDate = try c.decode(Bool.self, forKey: .upToDate)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        // l'etat est ecrit a plat, a cote des builds
        status = c.contains(.state) ? try UpdateStatus(from: decoder) : nil
    }
}

/// Ou en est la mise a jour d'un jeu du dossier Cidre : le meme objet dans
/// `cidre updates --json` (a plat), `cidre info --json` (`"maj"`) et les
/// evenements de `cidre play --json`.
public struct UpdateStatus: Decodable, Equatable, Sendable {
    public enum State: String, Sendable {
        case upToDate = "a_jour"
        /// Un build plus recent est publie.
        case available = "disponible"
        /// Son telechargement tourne (`progress`).
        case running = "en_cours"
        /// La derniere tentative a echoue (`reason`) ; le build reste a installer.
        case failed = "echouee"
        /// Un build plus recent existe, et on n'y va pas (`reason`).
        case ignored = "ignoree"
        case unknown = "inconnu"
        /// `cidre play` : Cidre demande a Steam s'il y a plus recent.
        case checking = "verification"
        /// `cidre play` : la mise a jour vient d'etre faite.
        case done = "faite"
    }

    /// Pourquoi une mise a jour a echoue, est laissee de cote, ou n'a pas pu
    /// etre verifiee.
    public enum Reason: String, Sendable {
        case session, steamcmd
        case disk = "disque"
        case network = "reseau"
        case license = "licence"
        case account = "compte"
        case interrupted = "interrompue"
        case option
        case branch = "branche"
        case noEffect = "sans_effet"
        case request = "demande"
        case offline = "hors_ligne"
        case slow = "trop_lent"
        case steamcmdMissing = "steamcmd_absent"
        case noBuild = "sans_build"
        case neverChecked = "jamais_verifie"
        /// Une raison que ce Verger ne connait pas (Cidre plus recent).
        case other = "autre"
    }

    public let state: State
    public let installedBuild: Int?
    public let availableBuild: Int?
    public let reason: Reason?
    /// Le message de Cidre, tel qu'il l'ecrit au terminal.
    public let message: String?
    /// L'avancement du telechargement en cours.
    public let progress: DownloadProgress?
    /// L'option `maj_avant_lancement` du jeu, resolue.
    public let beforeLaunch: Bool?

    enum CodingKeys: String, CodingKey {
        case state = "etat"
        case installedBuild = "build_installe"
        case availableBuild = "build_disponible"
        case reason = "raison"
        case message
        case percent = "avancement"
        case doneBytes = "octets"
        case totalBytes = "total"
        case beforeLaunch = "avant_lancement"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // un etat inconnu (Cidre plus recent) ne doit pas faire tomber la liste
        state = State(rawValue: try c.decode(String.self, forKey: .state)) ?? .unknown
        installedBuild = try c.decodeIfPresent(Int.self, forKey: .installedBuild)
        availableBuild = try c.decodeIfPresent(Int.self, forKey: .availableBuild)
        reason = try c.decodeIfPresent(String.self, forKey: .reason).map { Reason(rawValue: $0) ?? .other }
        message = try c.decodeIfPresent(String.self, forKey: .message)
        beforeLaunch = try c.decodeIfPresent(Bool.self, forKey: .beforeLaunch)
        if let percent = try c.decodeIfPresent(Double.self, forKey: .percent) {
            progress = DownloadProgress(
                fraction: min(max(percent / 100, 0), 1),
                doneBytes: try c.decodeIfPresent(Int64.self, forKey: .doneBytes) ?? 0,
                totalBytes: try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0)
        } else {
            progress = nil
        }
    }

    /// Ce qu'on dit au joueur d'une mise a jour qui n'a pas ete faite : la
    /// cause probable, et quoi faire. `nil` quand il n'y a rien a dire.
    public var explanation: String? {
        switch (state, reason) {
        case (.failed, .session):
            L10n.string("Mise à jour impossible : la session Steam n'est pas mémorisée. Connecte-toi (bouton +, « Connexion à Steam… »), puis relance le jeu.")
        case (.failed, .disk):
            L10n.string("Mise à jour impossible : il n'y a plus assez de place sur le disque des jeux. Libère de la place, puis relance le jeu.")
        case (.failed, .network):
            L10n.string("Mise à jour interrompue : la connexion à Steam a été perdue. Elle reprendra où elle en était au prochain lancement.")
        case (.failed, .license):
            L10n.string("Mise à jour impossible : ce compte Steam n'a pas ce jeu. Vérifie le compte connecté (Réglages → Steam).")
        case (.failed, .account):
            L10n.string("Mise à jour impossible : aucun compte Steam n'est connu. Connecte-toi (bouton +, « Connexion à Steam… »).")
        case (.failed, .interrupted):
            L10n.string("Mise à jour interrompue avant la fin. Elle reprendra où elle en était au prochain lancement.")
        case (.failed, _):
            L10n.string("La mise à jour a échoué : SteamCMD n'a pas pu la terminer. Relance le jeu pour réessayer.")
                + (message.map { "\n\($0)" } ?? "")
        case (.ignored, .option):
            L10n.string("Une mise à jour est disponible ; ce jeu n'est pas mis à jour au lancement (option « Mise à jour avant de jouer » coupée).")
        case (.ignored, .branch):
            L10n.string("Une mise à jour est disponible sur la branche publique ; ce jeu suit une branche bêta de Steam et n'est pas mis à jour au lancement.")
        case (.ignored, .noEffect):
            L10n.string("Steam annonce une version plus récente, mais ne la donne pas à ce compte : la mise à jour a déjà été tentée, sans effet.")
        case (.ignored, _):
            nil
        case (.unknown, .offline):
            L10n.string("Mise à jour non vérifiée : Steam n'a pas répondu (hors ligne ?).")
        case (.unknown, .slow):
            L10n.string("Mise à jour non vérifiée : Steam met trop de temps à répondre. Sa réponse servira au prochain lancement.")
        case (.unknown, .steamcmdMissing):
            L10n.string("Mise à jour non vérifiée : SteamCMD est introuvable. Réinstalle Cidre depuis les Réglages.")
        default:
            nil
        }
    }
}

/// Les shaders d'un jeu Windows sur ce Mac : `cidre info --json` (`"shaders"`)
/// et l'evenement `shaders` de `cidre play --json`, ecrit avant le lancement.
/// Au premier lancement, chaque shader est traduit puis compile par Metal pour
/// la puce : des minutes d'ecran noir ou de textures manquantes, une fois.
public struct ShaderCacheStatus: Decodable, Equatable, Sendable {
    public enum State: String, Sendable {
        /// Rien de compile pour ce jeu sur ce Mac, dans sa voie de rendu.
        case firstLaunch = "premier_lancement"
        /// Compile, mais a refaire (`reason`) : en general plus court.
        case invalidated = "cache_invalide"
        case cached = "en_cache"
        /// Un etat que ce Verger ne connait pas (Cidre plus recent).
        case unknown = "inconnu"
    }

    public enum Reason: String, Sendable {
        /// macOS a change : Metal recompile son binaire.
        case macOS = "macos"
        /// Un autre Mac (autre puce).
        case machine
        /// Cidre a change la traduction (voies KosmicKrisp : D3D12, DXVK).
        case cidre
        case other = "autre"
    }

    public let state: State
    public let reason: Reason?
    /// La voie de rendu du prochain lancement : dxmt, dxvk ou d3d12.
    public let renderer: String?
    /// La fin de la derniere partie notee par Cidre.
    public let lastRun: Date?
    /// Le message de Cidre, tel qu'il l'ecrit au terminal.
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case state = "etat"
        case reason = "raison"
        case renderer = "voie"
        case lastRun = "dernier"
        case message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = State(rawValue: try c.decode(String.self, forKey: .state)) ?? .unknown
        reason = try c.decodeIfPresent(String.self, forKey: .reason).map { Reason(rawValue: $0) ?? .other }
        renderer = try c.decodeIfPresent(String.self, forKey: .renderer)
        let epoch = try c.decodeIfPresent(Double.self, forKey: .lastRun) ?? 0
        lastRun = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }

    /// Ce qu'on annonce au joueur quand il lance le jeu ; `nil` : rien a dire.
    public var announcement: String? {
        switch (state, reason) {
        case (.firstLaunch, _):
            L10n.string("Premier lancement : les shaders du jeu sont compilés pour ce Mac. Cela peut prendre quelques minutes, pendant lesquelles le jeu peut afficher un écran noir ou des textures manquantes. Les lancements suivants seront plus rapides.")
        case (.invalidated, .macOS):
            L10n.string("macOS a été mis à jour depuis la dernière partie : Metal recompile les shaders du jeu. Ce lancement peut être plus long que d'habitude.")
        case (.invalidated, .machine):
            L10n.string("Premier lancement sur ce Mac : les shaders du jeu sont compilés pour sa puce. Cela peut prendre quelques minutes, pendant lesquelles le jeu peut afficher un écran noir ou des textures manquantes.")
        case (.invalidated, .cidre):
            L10n.string("Cidre a été mis à jour depuis la dernière partie : une partie des shaders du jeu peut être recompilée. Ce lancement peut être plus long que d'habitude.")
        case (.invalidated, _):
            message ?? L10n.string("Les shaders du jeu sont à recompiler : ce lancement peut être plus long que d'habitude.")
        case (.cached, _), (.unknown, _):
            nil
        }
    }

    /// L'etat en quelques mots, pour la fiche du jeu.
    public var summary: String {
        switch (state, reason) {
        case (.cached, _): L10n.string("Compilés sur ce Mac")
        case (.firstLaunch, _): L10n.string("À compiler au premier lancement")
        case (.invalidated, .macOS): L10n.string("À recompiler (macOS mis à jour)")
        case (.invalidated, .machine): L10n.string("À compiler pour ce Mac")
        case (.invalidated, .cidre): L10n.string("À recompiler en partie (Cidre mis à jour)")
        case (.invalidated, _): L10n.string("À recompiler")
        case (.unknown, _): L10n.string("Inconnu")
        }
    }
}

/// Ce que `cidre play <id> --json` ecrit sur sa sortie standard avant de lancer
/// le jeu, un objet JSON par ligne.
public enum PlayEvent: Equatable, Sendable {
    /// Ou en est la mise a jour d'avant lancement.
    case update(UpdateStatus)
    /// Les shaders du jeu sont-ils deja compiles sur ce Mac ?
    case shaders(ShaderCacheStatus)
    /// Le jeu part : plus rien ne suivra.
    case launching
    /// Cidre refuse de lancer : `hors_ligne` (disque debranche), `deplacement`
    /// (jeu en cours de deplacement).
    case refused(code: String, message: String)

    /// L'evenement que porte une ligne ; `nil` pour toute autre ligne (un Cidre
    /// plus ancien ecrit ici la sortie du lanceur).
    public static func parse(line: String) -> PlayEvent? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("{"), let data = line.data(using: .utf8),
              let kind = try? JSONDecoder().decode(Kind.self, from: data) else { return nil }
        switch kind.name {
        case "lancement": return .launching
        case "maj": return (try? JSONDecoder().decode(UpdateStatus.self, from: data)).map(PlayEvent.update)
        case "erreur":
            guard let refusal = try? JSONDecoder().decode(Refusal.self, from: data) else { return nil }
            return .refused(code: refusal.code, message: refusal.message ?? "")
        case "shaders": return (try? JSONDecoder().decode(ShaderCacheStatus.self, from: data)).map(PlayEvent.shaders)
        default: return nil
        }
    }

    private struct Kind: Decodable {
        let name: String
        enum CodingKeys: String, CodingKey { case name = "evenement" }
    }

    private struct Refusal: Decodable {
        let code: String
        let message: String?
    }
}

/// Ce que fait le bouton « Jouer » d'un jeu, d'apres ce qu'on sait de sa mise a jour.
public enum PlayPlan: Equatable, Sendable {
    /// Lancer : rien a mettre a jour, ou ce n'est pas a Cidre de le faire.
    case play
    /// Mettre a jour, puis lancer ; « Jouer sans mettre a jour » reste offert.
    case updateThenPlay

    public static func plan(for game: Game, update: GameUpdate?) -> PlayPlan {
        // Un jeu du client Steam, c'est Steam qui le met a jour (et il le fait
        // de lui-meme avant de le lancer) ; un jeu hors Steam n'a pas de build.
        guard game.source == .cidre, game.installed, let update, update.needsUpdate else { return .play }
        if let status = update.status {
            // laissee de cote : option coupee, branche beta, deja tentee sans effet
            if status.state == .ignored || status.beforeLaunch == false { return .play }
        }
        return .updateThenPlay
    }
}

/// L'avancement d'un `cidre dl`, lu dans la sortie de SteamCMD.
public struct DownloadProgress: Hashable, Sendable {
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

/// Le client Battle.net de Cidre, `cidre battlenet etat --json`.
public struct BattleNetStatus: Decodable, Sendable, Equatable {
    /// Le prefixe Wine ou vit le client.
    public let prefix: String
    public let installed: Bool
    public let open: Bool
    /// Le jeu pour lequel Cidre l'a ouvert (`client` : pour lui-meme).
    public let openFor: String?
    /// Le jeu Battle.net qui tourne, s'il y en a un.
    public let runningGame: String?
    public let gameCount: Int

    enum CodingKeys: String, CodingKey {
        case prefix = "prefixe"
        case installed = "installe"
        case open = "ouvert"
        case openFor = "pour"
        case runningGame = "jeu"
        case gameCount = "jeux"
    }
}
