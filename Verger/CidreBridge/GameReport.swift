import Foundation

/// « Partager mon résultat » : ce qu'un joueur dit d'un jeu sur sa machine,
/// ecrit au format des fiches `profils/<appid>.toml` de Cidre (`[[rapports]]`).
/// Verger n'envoie rien : il prepare un incident GitHub que l'utilisateur relit
/// et publie lui-meme.
public struct GameReport: Equatable, Sendable {
    /// Le verdict, tel que les fiches de Cidre le nomment.
    public enum Verdict: String, CaseIterable, Identifiable, Sendable {
        case gold = "or"
        case silver = "argent"
        case bronze = "bronze"
        case broken = "ko"

        public var id: Self { self }

        public var title: String {
            switch self {
            case .gold: L10n.string("Parfait")
            case .silver: L10n.string("Jouable avec des limites")
            case .bronze: L10n.string("Démarre mais lent ou bogué")
            case .broken: L10n.string("Ne marche pas")
            }
        }
    }

    /// Ce que Verger sait de la machine et de l'installation au moment du
    /// rapport. Chaque champ est `nil` quand ce Cidre ne sait pas le dire.
    public struct Context: Equatable, Sendable {
        /// « M1 Max 32 Go »
        public var machine: String?
        /// L'identifiant du modele (« Mac15,9 ») : la puce ne dit ni l'ecran ni le
        /// nombre de coeurs GPU, le modele les situe.
        public var model: String?
        /// La version de macOS (« 26.5.2 »), le fait `macos_version` de Cidre.
        public var macOS: String?
        public var cidreVersion: String?
        /// Le profil effectif du jeu : ses options de lancement resolues.
        public var options: LaunchOptions?
        /// Le diagnostic de l'installation, deja anonymise.
        public var diagnostic: String?
        /// La famille Metal de la carte graphique (`MTLGPUFamilyApple<N>` : 7 = M1,
        /// 8 = M2, 9 = M3 et M4), le fait `famille_gpu` des fiches.
        public var gpuFamily: Int?

        public init(machine: String? = nil, model: String? = nil, macOS: String? = nil, cidreVersion: String? = nil,
                    options: LaunchOptions? = nil, diagnostic: String? = nil, gpuFamily: Int? = nil) {
            self.machine = machine
            self.model = model
            self.macOS = macOS
            self.cidreVersion = cidreVersion
            self.options = options
            self.diagnostic = diagnostic
            self.gpuFamily = gpuFamily
        }

        /// La voie de rendu du lancement, comme les fiches la nomment : `d3d12`
        /// avec dx12, sinon le rendu Direct3D 11 (`dxmt`, `dxvk`). `nil` : options inconnues.
        public var route: String? {
            guard let options else { return nil }
            if options.dx12 == true { return "d3d12" }
            return options.d3d11.flatMap { ["dxmt", "dxvk"].contains($0) ? $0 : nil }
        }
    }

    /// Le jour du rapport, « AAAA-MM-JJ ».
    public var date: String
    public var context: Context
    public var verdict: Verdict
    public var fpsMenu: Int?
    public var fpsGame: Int?
    public var notes: String

    public init(date: String = GameReport.day(), context: Context = Context(), verdict: Verdict = .silver,
                fpsMenu: Int? = nil, fpsGame: Int? = nil, notes: String = "") {
        self.date = date
        self.context = context
        self.verdict = verdict
        self.fpsMenu = fpsMenu
        self.fpsGame = fpsGame
        self.notes = notes
    }

    /// Un jour au format des fiches, « 2026-10-11 », dans le fuseau de la machine.
    public static func day(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Une chaine TOML entre guillemets : guillemets, barres obliques inverses
    /// et sauts de ligne echappes, les caracteres de controle en `\uXXXX`.
    public static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""  // "
            case 0x5C: out += "\\\\"  // \
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case ..<0x20, 0x7F: out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    private static func line(_ key: String, _ value: String) -> String { key + " = " + value }

    /// La balise de tete d'un incident : la version du format et le jeu.
    public static func tag(gameID: String) -> String { "<!-- cidre-rapport v1 appid=\(gameID) -->" }

    /// Le bloc `[[rapports]]`, tel qu'il se colle dans la fiche du jeu. Les
    /// champs inconnus ou vides n'y figurent pas : TOML n'a pas de « rien ».
    /// Le champ `incident` (l'adresse de l'incident) est ajoute par le mainteneur.
    public var toml: String {
        var lines = ["[[rapports]]", Self.line("date", Self.quoted(date))]
        if let machine = context.machine, !machine.isEmpty { lines.append(Self.line("machine", Self.quoted(machine))) }
        if let model = context.model, !model.isEmpty { lines.append(Self.line("modele", Self.quoted(model))) }
        if let macOS = context.macOS, !macOS.isEmpty { lines.append(Self.line("macos_version", Self.quoted(macOS))) }
        // de quoi ranger le rapport par famille de Mac et par voie ([[compat.machines]] de la fiche)
        if let family = context.gpuFamily { lines.append(Self.line("famille_gpu", String(family))) }
        if let route = context.route { lines.append(Self.line("voie", Self.quoted(route))) }
        if let version = context.cidreVersion, !version.isEmpty { lines.append(Self.line("cidre_version", Self.quoted(version))) }
        lines.append(Self.line("etat", Self.quoted(verdict.rawValue)))
        if let fpsMenu { lines.append(Self.line("fps_menu", String(fpsMenu))) }
        if let fpsGame { lines.append(Self.line("fps_jeu", String(fpsGame))) }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append(Self.line("notes", Self.quoted(trimmed))) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Le profil effectif, en TOML : `[profil]` puis une option par ligne.
    public var profileToml: String? {
        guard let options = context.options else { return nil }
        return (["[profil]"] + options.tomlLines).joined(separator: "\n") + "\n"
    }

    /// Le texte de l'incident, sans le diagnostic : le rapport, puis le profil.
    public var text: String {
        let fence = "```"
        let open = fence + "toml"
        var text = open + "\n" + toml + fence + "\n"
        if let profileToml {
            text += "\n**" + L10n.string("Profil effectif") + "**\n" + open + "\n" + profileToml + fence + "\n"
        }
        return text
    }

    /// Le formulaire d'incident « Rapport de jeu » du depot de Cidre
    /// (`.github/ISSUE_TEMPLATE/rapport-jeu.yml`) et l'identifiant de son champ
    /// de texte. Les deux noms sont ceux du depot : les changer ici sans les
    /// changer la-bas ouvre une page vide.
    public static let issueTemplate = "rapport-jeu.yml"
    public static let issueField = "rapport"

    /// La plus longue adresse qu'on presente a GitHub : celle de tout incident.
    public static let maxURLLength = IssueReport.maxURLLength

    /// L'incident GitHub pret a partir : titre fixe (« Rapport de jeu : <nom>
    /// (<appid>) », en francais quelle que soit la langue de Verger, pour le tri
    /// cote Cidre), formulaire « Rapport de jeu » du depot (c'est lui qui pose
    /// le label `rapport-jeu`, pour n'importe quel auteur), le diagnostic en
    /// journal. Une adresse web ne porte que quelques kilo-octets : si le
    /// diagnostic n'y tient pas, c'est sa fin qui est coupee, pas son debut. Le
    /// texte commence par une balise que GitHub n'affiche pas,
    /// « <!-- cidre-rapport v1 appid=... --> » : l'outil de relecture de Cidre
    /// (tests/outils/rapports_vers_fiches.py) y lit le jeu meme si
    /// l'utilisateur a refait le titre.
    public func issue(gameName: String, gameID: String, repository: String = "gtranche/cidre") -> IssueReport {
        let diagnostic = (context.diagnostic ?? "").split(whereSeparator: \.isNewline).map(String.init)
        return IssueReport(
            repository: repository, title: "Rapport de jeu : \(gameName) (\(gameID))",
            text: Self.tag(gameID: gameID) + "\n" + text,
            logTitle: L10n.string("Diagnostic"), log: diagnostic,
            template: Self.issueTemplate, field: Self.issueField, truncation: .head)
    }
}

extension LaunchOptions {
    /// Les options en lignes TOML, sous les noms de Cidre (`tso = true`,
    /// `d3d11 = "dxvk"`). Celles que ce Cidre ne connait pas n'y sont pas.
    public var tomlLines: [String] {
        func line(_ key: Key, _ value: String) -> String { key.rawValue + " = " + value }
        var lines = [
            line(.tso, String(tso)), line(.vsync, String(vsync)), line(.hud, String(hud)),
            line(.asyncShaders, String(asyncShaders)), line(.compilerThreads, String(compilerThreads)),
            line(.eacUntrusted, String(eacUntrusted)), line(.luajit, String(luajit)),
        ]
        if let fullscreen { lines.append(line(.fullscreen, String(fullscreen))) }
        if let gameMode { lines.append(line(.gameMode, String(gameMode))) }
        if let overlay { lines.append(line(.overlay, String(overlay))) }
        if let narrowBarriers { lines.append(line(.narrowBarriers, String(narrowBarriers))) }
        if let dx12 { lines.append(line(.dx12, String(dx12))) }
        if let d3d11 { lines.append(line(.d3d11, GameReport.quoted(d3d11))) }
        if let metalfx { lines.append(line(.metalfx, String(metalfx))) }
        if let language { lines.append(line(.language, GameReport.quoted(language))) }
        return lines
    }
}

extension SystemInfo {
    /// La machine telle que les fiches de Cidre la nomment : « M1 Max 32 Go ».
    /// `nil` si la puce n'a pas pu etre lue.
    public var machineLabel: String? {
        let chip = chip.replacingOccurrences(of: "Apple ", with: "").trimmingCharacters(in: .whitespaces)
        guard !chip.isEmpty, memoryGB > 0 else { return nil }
        return [chip, String(memoryGB), "Go"].joined(separator: " ")
    }
}
