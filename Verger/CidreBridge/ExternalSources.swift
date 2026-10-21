import Foundation

/// Ce que les bases publiques disent d'un jeu, tel que l'import de Cidre l'a
/// repris dans sa fiche (`tests/outils/importer_profils.py`) : le `[jeu]`
/// importe (moteur, API, anti-triche, avec la source de chaque cle,
/// `"jeu_sources"`), les verdicts d'AppleGamingWiki, la recette CrossOver et
/// les emplacements de PCGamingWiki. Pour information : le lanceur de Cidre
/// n'applique rien de tout cela (hors la seule regle « D3D12 seul = D3D12 »,
/// qui se lit deja dans les options).
public struct ExternalSources: Equatable, Sendable {
    /// Une valeur du `[jeu]` et sa provenance (« pcgamingwiki 2026-10-15 ») ;
    /// `source` nil : ecrite ou verifiee a la main.
    public struct Fact: Equatable, Sendable {
        public let value: String
        public let source: String?
    }

    public let engine: Fact?
    /// Les API graphiques du jeu, dans l'ordre de la fiche (`api_disponibles`).
    public let apis: Fact?
    public let bits: Fact?
    public let antiCheat: AntiCheat?
    public let drm: Fact?
    public let appleGamingWiki: AppleGamingWiki?
    public let crossOver: CrossOver?
    public let pcGamingWiki: PCGamingWiki?

    /// L'anti-triche que nomme la fiche (`none` n'en est pas un).
    public struct AntiCheat: Equatable, Sendable {
        public let id: String
        public let name: String
        public let source: String?
        /// EAC, BattlEye : leur mode en ligne ne demarre pas sous Wine sur Mac.
        public var blocksOnline: Bool { id == "eac" || id == "battleye" }
    }

    /// Les verdicts d'AppleGamingWiki, une voie par entree.
    public struct AppleGamingWiki: Equatable, Sendable {
        public let verdicts: [(route: Route, verdict: Verdict)]
        public let lastReport: String?
        public let url: URL?

        public enum Route: String, CaseIterable, Sendable {
            case native = "natif", rosetta, crossover, wine, parallels

            public var title: String {
                switch self {
                case .native: L10n.string("Version Mac")
                case .rosetta: "Rosetta 2"
                case .crossover: "CrossOver"
                case .wine: L10n.string("Wine (GPTK, Whisky…)")
                case .parallels: "Parallels"
                }
            }
        }

        public static func == (a: Self, b: Self) -> Bool {
            a.lastReport == b.lastReport && a.url == b.url
                && a.verdicts.map(\.route) == b.verdicts.map(\.route) && a.verdicts.map(\.verdict) == b.verdicts.map(\.verdict)
        }
    }

    /// Les verdicts d'AppleGamingWiki traduits par l'import.
    public enum Verdict: String, Sendable {
        case perfect = "parfait", playable = "jouable", runs = "demarre", broken = "ko"

        public var title: String {
            switch self {
            case .perfect: L10n.string("Parfait")
            case .playable: L10n.string("Jouable")
            case .runs: L10n.string("Démarre")
            case .broken: L10n.string("Ne marche pas")
            }
        }
    }

    /// La recette CrossOver du jeu : des valeurs techniques seulement.
    public struct CrossOver: Equatable, Sendable {
        public let bottle: String?
        public let graphics: String?
        public let version: String?
        public let recipeDate: String?
        public let dllOverrides: String?
        public let dependencies: String?
        public let url: URL?
    }

    /// Ou le jeu range ses reglages et ses sauvegardes sous Windows, d'apres
    /// PCGamingWiki (chemins relatifs au dossier de l'utilisateur Wine).
    public struct PCGamingWiki: Equatable, Sendable {
        public let settingsFiles: [String]
        public let saves: [String]
        public let url: URL?
    }

    /// Rien a montrer.
    public var isEmpty: Bool {
        engine == nil && apis == nil && bits == nil && antiCheat == nil && drm == nil
            && appleGamingWiki == nil && crossOver == nil && pcGamingWiki == nil
    }

    public init(engine: Fact? = nil, apis: Fact? = nil, bits: Fact? = nil, antiCheat: AntiCheat? = nil, drm: Fact? = nil,
                appleGamingWiki: AppleGamingWiki? = nil, crossOver: CrossOver? = nil, pcGamingWiki: PCGamingWiki? = nil) {
        self.engine = engine
        self.apis = apis
        self.bits = bits
        self.antiCheat = antiCheat
        self.drm = drm
        self.appleGamingWiki = appleGamingWiki
        self.crossOver = crossOver
        self.pcGamingWiki = pcGamingWiki
    }

    /// Depuis les objets de la fiche (`"jeu"`, `"jeu_sources"`, `"applegamingwiki"`,
    /// `"crossover"`, `"pcgamingwiki"`) ; un Cidre qui ne rend pas les blocs importes
    /// ne donne que le `[jeu]`.
    init(game: [String: Scalar], sources: [String: Scalar], agw: [String: Scalar]?, crossOver co: [String: Scalar]?, pcgw: [String: Scalar]?) {
        // la valeur montree, et la source de la premiere cle qui en a une
        func fact(_ value: String?, _ keys: String...) -> Fact? {
            guard let value, !value.isEmpty else { return nil }
            return Fact(value: value, source: keys.lazy.compactMap { sources[$0]?.text }.first)
        }
        engine = fact(game["moteur_nom"]?.text ?? game["moteur"]?.text.flatMap { $0 == "autre" ? nil : Self.engineTitle($0) },
                      "moteur_nom", "moteur")
        apis = fact((game["api_disponibles"] ?? game["api"])?.text.map {
            $0.split(separator: " ").map { Self.apiTitle(String($0)) }.joined(separator: ", ")
        }, "api_disponibles", "api")
        bits = fact(game["bits"]?.text.map { L10n.format("%@ bits", $0) }, "bits")
        if let id = game["anticheat"]?.text, id != "none", !id.isEmpty {
            antiCheat = AntiCheat(id: id, name: game["anticheat_nom"]?.text ?? Self.antiCheatTitle(id), source: sources["anticheat"]?.text)
        } else {
            antiCheat = nil
        }
        drm = fact(game["drm"]?.text.map { $0.replacingOccurrences(of: " ; ", with: ", ") }, "drm")

        if let agw {
            let verdicts = AppleGamingWiki.Route.allCases.compactMap { r in
                agw[r.rawValue]?.text.flatMap(Verdict.init(rawValue:)).map { (route: r, verdict: $0) }
            }
            appleGamingWiki = verdicts.isEmpty ? nil
                : AppleGamingWiki(verdicts: verdicts, lastReport: agw["dernier_temoignage"]?.text, url: agw["url"]?.url)
        } else {
            appleGamingWiki = nil
        }
        if let co, co["recette"] != nil {
            crossOver = CrossOver(bottle: co["bouteille"]?.text, graphics: co["graphismes"]?.text, version: co["crossover_version"]?.text,
                                  recipeDate: co["recette_date"]?.text, dllOverrides: co["dll_overrides"]?.text,
                                  dependencies: co["dependances"]?.text, url: co["url"]?.url)
        } else {
            crossOver = nil
        }
        if let pcgw {
            let list = { (k: String) in (pcgw[k]?.text ?? "").components(separatedBy: " ; ").filter { !$0.isEmpty } }
            let p = PCGamingWiki(settingsFiles: list("fichiers_reglages"), saves: list("sauvegardes"), url: pcgw["url"]?.url)
            pcGamingWiki = p.settingsFiles.isEmpty && p.saves.isEmpty && p.url == nil ? nil : p
        } else {
            pcGamingWiki = nil
        }
    }

    static func apiTitle(_ id: String) -> String {
        switch id {
        case "d3d12": "Direct3D 12"
        case "d3d11": "Direct3D 11"
        case "d3d10": "Direct3D 10"
        case "d3d9": "Direct3D 9"
        case "d3d8": "Direct3D 8"
        case "d3d7": "Direct3D 7"
        case "d3d6": "Direct3D 6"
        case "d3d5": "Direct3D 5"
        case "d3d3": "Direct3D 3"
        case "ddraw": "DirectDraw"
        case "vulkan": "Vulkan"
        case "opengl": "OpenGL"
        case "glide": "Glide"
        case "metal": "Metal"
        default: id
        }
    }

    static func antiCheatTitle(_ id: String) -> String {
        switch id {
        case "eac": "Easy Anti-Cheat"
        case "battleye": "BattlEye"
        case "denuvo": "Denuvo Anti-Cheat"
        case "vac": "Valve Anti-Cheat (VAC)"
        default: id
        }
    }

    static func engineTitle(_ id: String) -> String {
        switch id {
        case "unreal": "Unreal Engine"
        case "unity": "Unity"
        case "hashlink": "HashLink"
        case "stingray": "Stingray"
        case "godot": "Godot"
        case "source": "Source"
        default: id
        }
    }

    /// Une valeur d'objet a plat de la fiche : chaine, nombre ou booleen.
    struct Scalar: Decodable, Sendable {
        let text: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { text = s }
            else if let i = try? c.decode(Int.self) { text = String(i) }
            else if let d = try? c.decode(Double.self) { text = String(d) }
            else if let b = try? c.decode(Bool.self) { text = b ? "true" : "false" }
            else { text = nil }
        }

        var url: URL? { text.flatMap(URL.init(string:)) }
    }
}
