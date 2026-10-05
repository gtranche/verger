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

    public init(repository: String, title: String, text: String, logTitle: String = "", log: [String] = []) {
        self.repository = repository
        self.title = title
        self.text = text
        self.logTitle = logTitle
        self.log = log
    }

    /// Le texte complet, avec les `lines` dernieres lignes du journal.
    public func body(logLines lines: Int? = nil) -> String {
        let kept = lines.map { Array(log.suffix($0)) } ?? log
        guard !kept.isEmpty else { return text }
        let fence = "```"
        return text + "\n\n**\(logTitle)**\n\(fence)text\n" + kept.joined(separator: "\n") + "\n\(fence)\n"
    }

    /// L'adresse de la page « nouvel incident » remplie. Une adresse ne porte que
    /// quelques kilo-octets : on y met autant de lignes de la fin du journal
    /// qu'il en tient, le reste part en piece jointe.
    public func url(maxLength: Int = 7000) -> URL {
        var lines = log.count
        while true {
            var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
            components.queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "body", value: body(logLines: lines)),
            ]
            // `+` doit etre encode : dans une adresse il se lirait comme un espace
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            if let url = components.url, url.absoluteString.utf8.count <= maxLength || lines == 0 {
                return url
            }
            lines = lines > 8 ? lines * 2 / 3 : lines - 1
            if lines < 0 { lines = 0 }
        }
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
