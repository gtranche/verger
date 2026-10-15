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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // une fiche sans [compat] rend {} : pas d'etat a montrer
        here = Self.status(try? c.decodeIfPresent(Status.self, forKey: .here))
        reference = Self.status(try? c.decodeIfPresent(Status.self, forKey: .reference))
        families = (try? c.decodeIfPresent([Status].self, forKey: .families)) ?? []
    }

    public init(here: Status?, reference: Status?, families: [Status]) {
        self.here = here
        self.reference = reference
        self.families = families
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

    /// La fiche ne dit rien de plus que « non teste ».
    public var isEmpty: Bool { here == nil && families.isEmpty }
}
