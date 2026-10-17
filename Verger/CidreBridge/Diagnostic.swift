import Foundation

/// L'archive de diagnostic d'un jeu, faite par `cidre diag <id> --json`
/// (tests/diag_cidre.sh cote Cidre) : deja masquee, rien n'est encore parti.
public struct DiagnosticArchive: Decodable, Equatable, Sendable {
    public struct Game: Decodable, Equatable, Sendable {
        public var id: String
        public var name: String

        enum CodingKeys: String, CodingKey { case id, name = "nom" }
    }

    public struct File: Decodable, Equatable, Sendable, Identifiable {
        public var name: String
        public var bytes: Int
        public var id: String { name }

        enum CodingKeys: String, CodingKey { case name = "nom", bytes = "octets" }
    }

    /// Le service de depot : configure sur ce Cidre ? l'archive y part-elle chiffree ?
    public struct Service: Decodable, Equatable, Sendable {
        public var configured: Bool
        public var encrypted: Bool

        enum CodingKeys: String, CodingKey { case configured = "configure", encrypted = "chiffre" }
    }

    public var archive: String
    public var folder: String
    public var bytes: Int
    public var format: String
    public var game: Game
    /// Le resume (20 lignes au plus) : ce que lit l'equipe en premier.
    public var summary: [String]
    public var files: [File]
    /// Ce qui a ete masque, par categorie (`chemin`, `compte_steam`, `email`...).
    public var masked: [String: Int]
    public var screenshot: Bool
    public var service: Service

    enum CodingKeys: String, CodingKey {
        case archive, folder = "dossier", bytes = "octets", format, game = "jeu", summary = "resume"
        case files = "fichiers", masked = "masques", screenshot = "capture", service
    }

    public var archiveURL: URL { URL(fileURLWithPath: archive) }
    public var folderURL: URL { URL(fileURLWithPath: folder, isDirectory: true) }

    /// Ce qui a ete masque, en clair et dans un ordre fixe : « 12 chemins
    /// personnels », « 1 compte Steam »... Les categories a zero n'y sont pas.
    public var maskedDescription: [String] {
        let order = ["chemin", "compte_steam", "identifiant_steam", "machine", "email", "ip", "jeton"]
        let known = order.compactMap { key in masked[key].map { (key, $0) } }
        let others = masked.filter { !order.contains($0.key) }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return (known + others).filter { $0.1 > 0 }.map { key, n in
            switch key {
            case "chemin": L10n.format("%lld noms ou chemins personnels", n)
            case "compte_steam": L10n.format("%lld noms de compte Steam", n)
            case "identifiant_steam": L10n.format("%lld identifiants Steam", n)
            case "machine": L10n.format("%lld noms ou numéros du Mac", n)
            case "email": L10n.format("%lld adresses e-mail", n)
            case "ip": L10n.format("%lld adresses IP ou réseau", n)
            case "jeton": L10n.format("%lld jetons ou identifiants", n)
            default: "\(n) \(key)"
            }
        }
    }
}

/// Un diagnostic envoye : le code a donner a l'equipe.
public struct DiagnosticReceipt: Decodable, Equatable, Sendable {
    /// « CIDRE-7K3P-Q9 »
    public var code: String
    /// Le jour ou le service l'efface, « AAAA-MM-JJ ».
    public var expires: String
    public var encrypted: Bool

    enum CodingKeys: String, CodingKey { case code, expires = "expire", encrypted = "chiffre" }
}

/// Pourquoi l'envoi n'a pas eu lieu. Dans tous les cas l'archive reste sur le
/// Mac : Verger propose alors de la montrer dans le Finder et d'ouvrir le
/// formulaire GitHub.
public enum DiagnosticSendError: Error, Equatable, LocalizedError, Sendable {
    /// Ce Cidre n'a pas d'adresse de service (code 3).
    case notConfigured(String)
    /// Le service ne repond pas : pas de reseau, ou service tombe (code 4).
    case network(String)
    /// Le service a refuse : taille, trop d'envois, jeton (code 5).
    case refused(String)
    /// L'archive n'a pas pu etre lue ou chiffree (code 6), ou autre echec.
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .notConfigured(m), let .network(m), let .refused(m), let .failed(m): m
        }
    }

    /// La reponse en erreur de `cidre diag envoyer --json` :
    /// `{"erreur":"non_configure"|"reseau"|"refuse"|"archive","message":...}`.
    static func from(status: Int32, output: Data, stderr: Data) -> DiagnosticSendError {
        struct Answer: Decodable { var erreur: String?; var message: String? }
        let answer = try? JSONDecoder().decode(Answer.self, from: output)
        let message = answer?.message ?? String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        switch (answer?.erreur, status) {
        case ("non_configure", _), (nil, 3): return .notConfigured(message)
        case ("reseau", _), (nil, 4): return .network(message)
        case ("refuse", _), (nil, 5): return .refused(message)
        default: return .failed(message.isEmpty ? L10n.format("cidre diag envoyer : code %lld", Int(status)) : message)
        }
    }
}

extension CidreCLI {
    /// `cidre diag <id> --json` : fait l'archive de diagnostic, masquee, sans
    /// rien envoyer. `screenshot` : une capture de l'ecran entier, trois
    /// secondes apres l'appel, seulement si l'utilisateur l'a demandee.
    public func makeDiagnostic(id: String, screenshot: Bool = false, vergerVersion: String? = nil) async throws -> DiagnosticArchive {
        var arguments = ["diag", id, "--json"]
        if screenshot { arguments.append("--capture") }
        if let vergerVersion { arguments += ["--verger", vergerVersion] }
        return try await json(arguments)
    }

    /// `cidre diag envoyer <archive> --json`, apres l'accord de l'utilisateur.
    public func sendDiagnostic(archive: URL) async throws -> DiagnosticReceipt {
        let result = try await run(["diag", "envoyer", archive.path, "--json"])
        guard result.status == 0 else {
            throw DiagnosticSendError.from(status: result.status, output: result.stdout, stderr: result.stderr)
        }
        do {
            return try JSONDecoder().decode(DiagnosticReceipt.self, from: result.stdout)
        } catch {
            throw DiagnosticSendError.failed(String(decoding: result.stdout, as: UTF8.self))
        }
    }
}

extension DiagnosticArchive {
    /// Le repli sans service (pas de reseau, Cidre sans adresse de depot) : le
    /// formulaire « Rapport de jeu » de Cidre (rapport-jeu.yml), rempli comme
    /// « Partager mon résultat » -- modele du Mac et version de macOS compris --,
    /// avec le verdict « ne marche pas », le resume du diagnostic en journal, et
    /// l'archive a glisser dans l'incident (GitHub accepte le .tar.gz).
    public func fallbackIssue(context: GameReport.Context) -> IssueReport {
        var context = context
        context.diagnostic = summary.joined(separator: "\n")
        let name = game.name.isEmpty ? game.id : game.name
        let notes = L10n.format("Diagnostic joint à l'incident : %@ (envoi impossible depuis Verger).", archiveURL.lastPathComponent)
        return GameReport(context: context, verdict: .broken, notes: notes).issue(gameName: name, gameID: game.id)
    }
}
