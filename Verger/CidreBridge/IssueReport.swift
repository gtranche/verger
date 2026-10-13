import Foundation
import SystemConfiguration

/// Retire d'un texte ce qui identifie l'utilisateur, avant qu'il ne parte dans
/// un incident public : son nom de session (dans les chemins), ses identifiants
/// Steam, le nom de son Mac, les adresses de courriel. Et les codes de couleur
/// du terminal, qui rendent un journal illisible.
public struct Anonymizer: Sendable {
    /// Le nom de session macOS, tel qu'il apparait dans `/Users/<nom>`.
    public var user: String
    /// L'identifiant de connexion Steam, s'il est connu.
    public var steamAccount: String?
    /// Les noms sous lesquels le Mac se presente.
    public var hostNames: [String]

    public init(user: String, steamAccount: String? = nil, hostNames: [String] = []) {
        self.user = user
        self.steamAccount = steamAccount
        self.hostNames = hostNames
    }

    /// Celui de cette machine.
    public static func current(steamAccount: String? = nil) -> Anonymizer {
        Anonymizer(user: NSUserName(), steamAccount: steamAccount, hostNames: localHostNames())
    }

    /// Les noms de ce Mac, lus sur place. Surtout pas `ProcessInfo.hostName` :
    /// il interroge le reseau et peut geler l'application de longues secondes.
    public static func localHostNames() -> [String] {
        var names: [String] = []
        var buffer = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) == 0 {
            let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // « MacBook-Pro-de-Marie.local », et sans son suffixe
            names.append(name)
            if let dot = name.firstIndex(of: ".") { names.append(String(name[..<dot])) }
        }
        // le nom donne dans Reglages > General > Partage (« MacBook Pro de Marie »)
        if let friendly = SCDynamicStoreCopyComputerName(nil, nil) as String? { names.append(friendly) }
        return names.filter { !$0.isEmpty }
    }

    public func clean(_ text: String) -> String {
        var t = text
        func replace(_ pattern: String, _ template: String, literal: Bool = false) {
            let p = literal ? NSRegularExpression.escapedPattern(for: pattern) : pattern
            guard let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return }
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: template)
        }
        // les couleurs du terminal, avec ou sans leur caractere d'echappement
        replace("\u{1B}\\[[0-9;]*[A-Za-z]", "")
        replace("\\[[0-9]{1,2}(;[0-9]{1,2})*m", "")
        // le nom de session, dans un chemin macOS ou Windows (C:\users\nom, Z:\Users\nom)
        if !user.isEmpty {
            replace("([/\\\\]users[/\\\\])" + NSRegularExpression.escapedPattern(for: user) + "(?![A-Za-z0-9_.-])", "$1…")
        }
        // les identifiants Steam : SteamID64, [U:1:compte], dossier userdata/compte
        replace("7656119[0-9]{10}", "7656119…")
        replace("\\[U:1:[0-9]+\\]", "[U:1:…]")
        replace("(userdata[/\\\\])[0-9]+", "$1…")
        // l'identifiant de connexion Steam, en mot entier
        if let steamAccount, steamAccount.count >= 3 {
            replace("(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: steamAccount) + "(?![A-Za-z0-9_])", "‹steam›")
        }
        for name in hostNames where name.count >= 4 {
            replace(name, "‹mac›", literal: true)
        }
        replace("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", "‹mail›")
        return t
    }
}

/// Le Mac sur lequel tourne Verger, pour situer un rapport.
public struct SystemInfo: Equatable, Sendable {
    public var macOS: String
    /// L'identifiant du modele (« Mac15,9 »).
    public var model: String
    /// La puce (« Apple M3 Max »).
    public var chip: String
    public var memoryGB: Int

    public init(macOS: String, model: String, chip: String, memoryGB: Int) {
        self.macOS = macOS
        self.model = model
        self.chip = chip
        self.memoryGB = memoryGB
    }

    public static var current: SystemInfo {
        func sysctl(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return SystemInfo(
            macOS: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            model: sysctl("hw.model"), chip: sysctl("machdep.cpu.brand_string"),
            memoryGB: Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()))
    }

    public var summary: String {
        let memory = L10n.format("%lld Go de mémoire", memoryGB)
        return "macOS \(macOS) · \(model) · \(chip) · \(memory)"
    }
}

/// Un incident GitHub prepare par Verger : son titre, son texte, et la fin d'un
/// journal. Verger n'envoie rien : il ouvre la page « nouvel incident » de
/// GitHub deja remplie, et c'est l'utilisateur qui relit et envoie.
public struct IssueReport: Equatable, Sendable {
    /// Le depot ou va l'incident (« gtranche/cidre »).
    public var repository: String
    public var title: String
    /// Le texte de l'incident, sans le journal.
    public var text: String
    /// L'intitule du journal, puis ses lignes (la fin du journal d'un jeu).
    public var logTitle: String
    public var log: [String]
    /// Le formulaire d'incident du depot (« rapport-jeu.yml », dans
    /// `.github/ISSUE_TEMPLATE/`), ou `nil` pour un incident libre. C'est le
    /// formulaire qui pose le label, quel que soit l'auteur : un `labels=` dans
    /// l'adresse exige le droit de poser un label sur le depot, et GitHub rend
    /// une page 404 a qui ne l'a pas (sa documentation, « Creating an issue
    /// from a URL query »). Un joueur ne l'a jamais : pas de `labels=` ici.
    public var template: String?
    /// Le parametre d'adresse qui porte le texte : `body` pour un incident
    /// libre, l'identifiant (`id`) du champ de texte pour un formulaire.
    public var field: String
    /// Quand le journal ne tient pas dans l'adresse : garder sa fin (un journal
    /// de jeu, dont les dernieres lignes disent l'erreur) ou son debut (un
    /// diagnostic, qui commence par l'essentiel).
    public enum Truncation: Sendable { case tail, head }
    public var truncation: Truncation

    public init(repository: String, title: String, text: String, logTitle: String = "", log: [String] = [],
                template: String? = nil, field: String = "body", truncation: Truncation = .tail) {
        self.repository = repository
        self.title = title
        self.text = text
        self.logTitle = logTitle
        self.log = log
        self.template = template
        self.field = field
        self.truncation = truncation
    }

    /// Le texte complet, avec `lines` lignes du journal (sa fin, ou son debut
    /// suivi d'une marque de coupure, selon `truncation`).
    public func body(logLines lines: Int? = nil) -> String {
        var kept = log
        if lines == 0 {
            kept = []
        } else if let lines, lines < log.count {
            kept = truncation == .tail ? Array(log.suffix(lines)) : Array(log.prefix(lines)) + ["[…]"]
        }
        guard !kept.isEmpty else { return text }
        let fence = "```"
        return text + "\n\n**\(logTitle)**\n\(fence)text\n" + kept.joined(separator: "\n") + "\n\(fence)\n"
    }

    /// La page « nouvel incident » avec ces parametres, dans l'ordre.
    private func address(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
        components.queryItems = (template.map { [URLQueryItem(name: "template", value: $0)] } ?? []) + items
        // `+` doit etre encode : dans une adresse il se lirait comme un espace
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    private func address(logLines: Int) -> URL {
        address([URLQueryItem(name: "title", value: title), URLQueryItem(name: field, value: body(logLines: logLines))])
    }

    /// La longueur d'une adresse telle que GitHub la recoit. Un utilisateur qui
    /// n'est pas connecte dans son navigateur est renvoye vers
    /// `/login?return_to=<adresse>`, ou l'adresse est encodee une seconde fois
    /// (`%C3` devient `%25C3`) : avec `throughLogin`, c'est cette forme, la plus
    /// longue, qui est mesuree. Trop longue, GitHub l'abandonne et l'utilisateur
    /// arrive, une fois connecte, sur une page sans son texte.
    public static func length(of url: URL, throughLogin: Bool = false) -> Int {
        let direct = url.absoluteString.utf8.count
        guard throughLogin else { return direct }
        // une adresse est deja en ASCII : seuls lettres, chiffres et « - . _ » y restent tels quels
        let kept = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: kept) ?? url.absoluteString
        return "https://github.com/login?return_to=".utf8.count + encoded.utf8.count
    }

    /// L'adresse de la page « nouvel incident » remplie. Une adresse ne porte que
    /// quelques kilo-octets : on y met autant de lignes de la fin du journal
    /// qu'il en tient, le reste part en piece jointe.
    public func url(maxLength: Int = 7000, throughLogin: Bool = false) -> URL {
        var lines = log.count
        while true {
            let url = address(logLines: lines)
            if Self.length(of: url, throughLogin: throughLogin) <= maxLength || lines == 0 {
                return url
            }
            lines = lines > 8 ? lines * 2 / 3 : lines - 1
            if lines < 0 { lines = 0 }
        }
    }

    /// L'adresse sans le texte : le formulaire et le titre seuls. Pour un texte
    /// qui ne tient pas dans une adresse, meme sans journal.
    public var shortURL: URL { address([URLQueryItem(name: "title", value: title)]) }

    /// Par ou le texte arrive a GitHub.
    public enum Delivery: Equatable, Sendable {
        /// Dans l'adresse. `complete` est faux quand le journal y est coupe.
        case address(URL, complete: Bool)
        /// Le texte seul deborde deja de l'adresse : la page s'ouvre sans lui,
        /// et il est a coller depuis le presse-papiers.
        case clipboard(URL)
    }

    public func delivery(maxLength: Int = 7000, throughLogin: Bool = false) -> Delivery {
        let url = url(maxLength: maxLength, throughLogin: throughLogin)
        if Self.length(of: url, throughLogin: throughLogin) > maxLength { return .clipboard(shortURL) }
        return .address(url, complete: url == address(logLines: log.count))
    }
}

extension CidreCLI {
    /// `cidre log <id> [lignes]` : la fin du journal du dernier lancement d'un
    /// jeu, sans les lignes de trace. Vide si le jeu n'a pas de journal.
    public func log(id: String, lines: Int = 200) async throws -> [String] {
        let result = try await checked(["log", id, String(lines)])
        return String(decoding: result.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline).map(String.init)
    }
}
