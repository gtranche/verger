import Foundation

/// Ce que la fiche d'un jeu (base de profils de Cidre, `"fiche"` de
/// `cidre info --json`) dit de sa compatibilite : sur CE Mac, sur la machine
/// de reference, et famille de Mac par famille (`[[compat.machines]]`, voir
/// profils/README.md de Cidre).
public struct GameCompatibility: Decodable, Equatable, Sendable {
    /// L'etat sur ce Mac : l'entree par famille qui vaut ici, sinon `[compat]`.
    public let here: Status?
    /// Le `[compat]` ecrit : la machine de reference. `nil` : Cidre <= 1.5.11
    /// (alors `here` est ce `[compat]`).
    public let reference: Status?
    /// Toutes les entrees par famille, dans l'ordre de la fiche ; vide pour un
    /// Cidre <= 1.5.11 ou une fiche qui n'en a pas.
    public let families: [Status]
    /// Le resume ProtonDB importe dans la fiche (`"protondb"`) : des joueurs
    /// sous Linux (Proton), pas sur Mac. `nil` : la fiche n'en a pas, ou Cidre
    /// ne le rend pas encore.
    public let protonDB: ProtonDBSummary?
    /// Fiche provisoire (`"origine":"provisoire"`) : ecrite par Cidre a
    /// l'installation d'un jeu que la base ne connaissait pas, avec le seul
    /// resume ProtonDB.
    public let provisional: Bool
    /// Ce que disent les autres bases publiques (PCGamingWiki, AppleGamingWiki,
    /// CrossOver) et le `[jeu]` importe, pour information. `nil` : rien.
    public let external: ExternalSources?

    /// Le resume public de ProtonDB, tel que la fiche le porte (`[compat.protondb]`).
    public struct ProtonDBSummary: Decodable, Equatable, Sendable {
        public let tier: ProtonDBTier
        /// La tendance recente (`"tendance"`), le meilleur palier rapporte.
        public let trendingTier: ProtonDBTier?
        public let bestTier: ProtonDBTier?
        /// Le nombre de rapports derriere le palier ; `nil` : inconnu.
        public let reports: Int?
        /// `strong`, `good`, `moderate`, `low`... tel quel.
        public let confidence: String?
        public let url: URL?

        enum CodingKeys: String, CodingKey {
            case tier = "palier", trendingTier = "tendance", bestTier = "meilleur_palier"
            case reports = "rapports", confidence = "confiance", url
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // sans palier (fiche nourrie par l'export seul), pas de resume a montrer
            guard let tier = (try? c.decodeIfPresent(String.self, forKey: .tier)).flatMap(ProtonDBTier.init(rawValue:)) else {
                throw DecodingError.keyNotFound(CodingKeys.tier, .init(codingPath: c.codingPath, debugDescription: "pas de palier"))
            }
            self.tier = tier
            trendingTier = (try? c.decodeIfPresent(String.self, forKey: .trendingTier)).flatMap(ProtonDBTier.init(rawValue:))
            bestTier = (try? c.decodeIfPresent(String.self, forKey: .bestTier)).flatMap(ProtonDBTier.init(rawValue:))
            reports = try? c.decodeIfPresent(Int.self, forKey: .reports)
            confidence = try? c.decodeIfPresent(String.self, forKey: .confidence)
            url = (try? c.decodeIfPresent(String.self, forKey: .url)).flatMap(URL.init(string:))
        }
    }

    /// Les paliers de ProtonDB.
    public enum ProtonDBTier: String, Sendable {
        case platinum, gold, silver, bronze, borked, pending

        public var title: String {
            switch self {
            case .platinum: L10n.string("Platine")
            case .gold: L10n.string("Or")
            case .silver: L10n.string("Argent")
            case .bronze: L10n.string("Bronze")
            case .borked: L10n.string("Ne marche pas")
            case .pending: L10n.string("En attente")
            }
        }
    }

    /// Un etat de compatibilite : `[compat]` ou une entree `[[compat.machines]]`.
    public struct Status: Decodable, Equatable, Sendable {
        public let verdict: Verdict
        /// La voie de rendu dont parle l'etat (`dxmt`, `d3d12`...). `nil` : non dite.
        public let route: Route?
        /// Le libelle de l'entree par famille (« M2 et suivants »).
        public let name: String?
        /// Sur ce Mac, l'entree par famille retenue (`"pour"` de `"compat"`).
        public let scope: String?
        /// L'entree vaut sur ce Mac (`"applique"`). `nil` : pas une entree par famille.
        public let applies: Bool?
        /// La machine de la mesure (« iMac M4 24 Go »).
        public let machine: String?
        public let date: String?
        public let cidreVersion: String?
        public let source: String?
        /// 0 ou absent : non mesure.
        public let fpsMenu: Int?
        public let fpsGame: Int?
        public let notes: String?
        /// Ce qu'il faut regler pour cette voie (« dx12=true sm66=true »).
        public let options: String?

        enum CodingKeys: String, CodingKey {
            case verdict = "etat", route = "voie", name = "nom", scope = "pour", applies = "applique"
            case machine, date, source, notes, options
            case cidreVersion = "cidre_version", fpsMenu = "fps_menu", fpsGame = "fps_jeu"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            verdict = Verdict(rawValue: (try? c.decodeIfPresent(String.self, forKey: .verdict)) ?? "") ?? .untested
            route = (try? c.decodeIfPresent(String.self, forKey: .route)).map(Route.init(rawValue:))
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            scope = try? c.decodeIfPresent(String.self, forKey: .scope)
            applies = try? c.decodeIfPresent(Bool.self, forKey: .applies)
            machine = try? c.decodeIfPresent(String.self, forKey: .machine)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            cidreVersion = try? c.decodeIfPresent(String.self, forKey: .cidreVersion)
            source = try? c.decodeIfPresent(String.self, forKey: .source)
            fpsMenu = (try? c.decodeIfPresent(Int.self, forKey: .fpsMenu)).flatMap { $0 > 0 ? $0 : nil }
            fpsGame = (try? c.decodeIfPresent(Int.self, forKey: .fpsGame)).flatMap { $0 > 0 ? $0 : nil }
            notes = try? c.decodeIfPresent(String.self, forKey: .notes)
            options = try? c.decodeIfPresent(String.self, forKey: .options)
        }
    }

    /// Le verdict, tel que les fiches le nomment.
    public enum Verdict: String, Sendable {
        case gold = "or", silver = "argent", bronze = "bronze", broken = "ko", untested = "non-teste"

        public var title: String {
            switch self {
            case .gold: L10n.string("Or")
            case .silver: L10n.string("Argent")
            case .bronze: L10n.string("Bronze")
            case .broken: L10n.string("Ne marche pas")
            case .untested: L10n.string("Non testé")
            }
        }

        public var explanation: String {
            switch self {
            case .gold: L10n.string("Parfait")
            case .silver: L10n.string("Jouable avec des limites")
            case .bronze: L10n.string("Démarre mais lent ou bogué")
            case .broken: L10n.string("Ne marche pas")
            case .untested: L10n.string("Pas encore essayé avec Cidre")
            }
        }
    }

    /// La voie de rendu : ce qui traduit les graphismes du jeu pour Metal.
    public struct Route: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public var title: String {
            switch rawValue {
            case "dxmt": "Direct3D 11 (DXMT)"
            case "dxvk": "Direct3D 11 (DXVK)"
            case "d3d12": "Direct3D 12"
            case "wined3d": "WineD3D"
            case "natif": L10n.string("Natif")
            default: rawValue
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case here = "compat", reference = "compat_reference", families = "compat_machines"
        case protonDB = "protondb", origin = "origine"
        case game = "jeu", gameSources = "jeu_sources", appleGamingWiki = "applegamingwiki"
        case crossOver = "crossover", pcGamingWiki = "pcgamingwiki"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // une fiche sans [compat] rend {} : pas d'etat a montrer
        here = Self.status(try? c.decodeIfPresent(Status.self, forKey: .here))
        reference = Self.status(try? c.decodeIfPresent(Status.self, forKey: .reference))
        families = (try? c.decodeIfPresent([Status].self, forKey: .families)) ?? []
        protonDB = try? c.decodeIfPresent(ProtonDBSummary.self, forKey: .protonDB)
        provisional = (try? c.decodeIfPresent(String.self, forKey: .origin)) == "provisoire"
        typealias Object = [String: ExternalSources.Scalar]
        let object = { (k: CodingKeys) in (try? c.decodeIfPresent(Object.self, forKey: k)) ?? nil }
        let external = ExternalSources(game: object(.game) ?? [:], sources: object(.gameSources) ?? [:],
                                       agw: object(.appleGamingWiki), crossOver: object(.crossOver), pcgw: object(.pcGamingWiki))
        self.external = external.isEmpty ? nil : external
    }

    public init(here: Status?, reference: Status?, families: [Status], protonDB: ProtonDBSummary? = nil, provisional: Bool = false,
                external: ExternalSources? = nil) {
        self.here = here
        self.reference = reference
        self.families = families
        self.protonDB = protonDB
        self.provisional = provisional
        self.external = external
    }

    private static func status(_ s: Status?) -> Status? {
        guard let s, s.verdict != .untested || s.notes != nil else { return nil }
        return s
    }

    /// Les autres rendus sur ce Mac : les entrees qui y valent et parlent
    /// d'une autre voie que l'etat retenu (le D3D12 d'un jeu regle en DXMT,
    /// bronze sur M4, ko sur M1).
    public var otherRoutesHere: [Status] {
        families.filter { $0.applies == true && $0.route != here?.route }
    }

    /// Ce que la fiche dit des autres Mac : les entrees qui ne valent pas ici.
    public var elsewhere: [Status] {
        families.filter { $0.applies == false }
    }

    /// La fiche ne dit rien de plus que « non teste » (ni resume ProtonDB, ni
    /// autre source).
    public var isEmpty: Bool { here == nil && families.isEmpty && protonDB == nil && external == nil }
}
