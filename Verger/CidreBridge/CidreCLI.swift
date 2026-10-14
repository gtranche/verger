import Foundation

public enum CidreError: Error, LocalizedError, Sendable, Equatable {
    /// La commande a rendu un code non nul ; `message` porte sa sortie d'erreur.
    case commandFailed(command: String, status: Int32, message: String)
    /// La sortie n'est pas le JSON attendu (CLI trop ancienne, sans `--json` ?).
    case invalidOutput(command: String, underlying: String)
    /// SteamCMD n'a pas de session memorisee : il faut se connecter (`cidre login`).
    case steamSessionMissing
    /// `cidre play` refuse de lancer un jeu dont une mise a jour tourne deja
    /// ailleurs (code 4) : il serait pris a moitie remplace.
    case updateRunning
    /// `cidre play` refuse de lancer un jeu (code 7) : le client Steam croit sur
    /// ce Mac des sauvegardes qui n'y sont plus (`files`), et les retirerait du
    /// nuage a la sortie du jeu. Relancer avec `acceptCloudLoss` passe outre.
    case cloudSavesAtRisk(files: [String])

    public var errorDescription: String? {
        switch self {
        case .updateRunning:
            return L10n.string("Une mise à jour de ce jeu est déjà en cours : attends sa fin, puis relance-le.")
        case let .cloudSavesAtRisk(files):
            return L10n.format("Des sauvegardes que Steam croit sur ce Mac n'y sont plus : %@. Le jeu n'a pas été lancé, pour que Steam ne les retire pas du nuage.", files.joined(separator: ", "))
        case let .commandFailed(command, status, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return L10n.format("`cidre %@` a échoué (code %lld)", command, Int(status)) + (detail.isEmpty ? "." : " : \(detail)")
        case let .invalidOutput(command, underlying):
            return L10n.format("Sortie de `cidre %@` illisible — Cidre est-il à jour ? (%@)", command, underlying)
        case .steamSessionMissing:
            return L10n.string("La session Steam n'est pas mémorisée : connecte-toi (bouton +, « Connexion à Steam… »).")
        }
    }
}

/// La CLI `cidre` : la seule frontiere entre Verger et le runtime.
/// Verger ne reimplemente rien, il appelle ces commandes et lit leur JSON.
public struct CidreCLI: Sendable {
    public let executable: URL
    /// Le compte Steam a utiliser (`CIDRE_STEAM_USER`). Sans lui, Cidre prend
    /// celui que le client Steam a memorise.
    public var steamUser: String?

    public init(executable: URL, steamUser: String? = nil) {
        self.executable = executable
        self.steamUser = steamUser
    }

    /// L'environnement des commandes lancees : celui de Verger, plus le compte Steam.
    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let steamUser, !steamUser.isEmpty { environment["CIDRE_STEAM_USER"] = steamUser }
        return environment
    }

    // MARK: Detection

    /// Emplacements ou chercher la CLI, du plus explicite au plus general :
    /// le choix de l'utilisateur, `VERGER_CIDRE`, le Cidre que Verger installe
    /// lui-meme, puis le PATH.
    public static func candidates(
        userChoice: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var paths: [String] = []
        if let userChoice, !userChoice.isEmpty { paths.append(userChoice) }
        if let env = environment["VERGER_CIDRE"], !env.isEmpty { paths.append(env) }
        paths.append(RuntimeInstaller.defaultHome(environment: environment, userHome: home)
            .appendingPathComponent("cidre/cidre").path)
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            paths.append("\(dir)/cidre")
        }
        return paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// La premiere CLI trouvee, ou `nil` si Cidre n'est pas installe.
    public static func locate(
        userChoice: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CidreCLI? {
        let fm = FileManager.default
        for url in candidates(userChoice: userChoice, environment: environment, home: home) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return CidreCLI(executable: url)
            }
        }
        return nil
    }

    // MARK: Bibliotheque

    /// `cidre list --json`
    public func list() async throws -> [Game] {
        try await json(["list", "--json"])
    }

    /// `cidre info <id> --json`
    public func info(id: String) async throws -> GameInfo {
        try await json(["info", id, "--json"])
    }

    /// `cidre doctor` : le diagnostic de l'installation -- ce qui est la, ce qui
    /// tourne, et si Wine demarre, avec ses messages d'erreur. Dure jusqu'a une
    /// minute. Rend le texte tel que Cidre l'ecrit.
    public func doctor() async throws -> String {
        let result = try await run(["doctor"])
        let text = String(decoding: result.stdout, as: UTF8.self) + String(decoding: result.stderr, as: UTF8.self)
        // un Cidre d'avant `cidre doctor` repond par son mode d'emploi
        guard text.contains("== ") else {
            throw CidreError.invalidOutput(command: "doctor", underlying: String(text.prefix(80)))
        }
        return text
    }

    /// Une option de lancement lue par son nom dans `cidre info --json`, pour
    /// celles que Verger ne connait pas (encore) comme interrupteur.
    public func boolOption(id: String, named key: String) async -> Bool? {
        guard let result = try? await checked(["info", id, "--json"]),
              let info = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              let options = info["options"] as? [String: Any] else { return nil }
        return options[key] as? Bool
    }

    public func setOption(id: String, named key: String, to value: Bool) async throws {
        _ = try await checked(["set", id, key, value ? "true" : "false"])
    }

    /// `cidre stop [<id>]` : force l'arret d'un jeu lance par Cidre -- et de tout
    /// ce que Wine fait tourner, qui n'a qu'un prefixe. Sans `id` : tout arreter.
    public func stop(id: String? = nil) async throws {
        _ = try await checked(["stop"] + (id.map { [$0] } ?? []))
    }

    /// `cidre running --json` : les identifiants des jeux en cours, qu'ils aient
    /// ete lances par Verger, par Steam ou au Terminal.
    public func running() async throws -> [String] {
        try await json(["running", "--json"])
    }

    /// `cidre play <id>`. Rend la main quand la commande se termine : tout de
    /// suite pour un jeu lance par Steam, a la sortie du jeu sinon. La sortie
    /// de la commande va dans `log`.
    public func play(id: String, log: URL? = nil, acceptCloudLoss: Bool = false) async throws {
        do {
            try await runLogged(["play", id] + (acceptCloudLoss ? ["--accord-nuage"] : []), log: log)
        } catch let CidreError.commandFailed(_, status, _) where status == 7 {
            throw CidreError.cloudSavesAtRisk(files: Self.cloudGuardFiles(in: log))
        }
    }

    /// Les sauvegardes que la garde de Cidre (tests/garde_nuage_steam.sh) dit
    /// manquantes, lues dans le journal du lancement : les lignes en retrait qui
    /// suivent « … que Steam croit sur ce Mac n'y sont plus : ».
    public static func cloudGuardFiles(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.lastIndex(where: { $0.contains("que Steam croit sur ce Mac n'y sont plus :") }) else { return [] }
        var files: [String] = []
        for line in lines[(start + 1)...] {
            guard line.hasPrefix("       "), !line.trimmingCharacters(in: .whitespaces).hasPrefix("saves:") else { break }
            let file = line.trimmingCharacters(in: .whitespaces)
            if !file.isEmpty { files.append(file) }
        }
        return files
    }

    static func cloudGuardFiles(in log: URL?) -> [String] {
        guard let log, let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return cloudGuardFiles(in: text)
    }

    /// `cidre play <id> --json` : avant de lancer un jeu du dossier Cidre, Cidre
    /// le met a jour si Steam publie un build plus recent, et le raconte par
    /// `onEvent` (verification, avancement, echec et pourquoi, puis lancement).
    /// `skipUpdate` : jouer tout de suite (`--sans-maj`). Rend la main quand la
    /// commande se termine, comme `play(id:log:)`. Annuler la tache arrete la
    /// commande : pendant la mise a jour, SteamCMD s'arrete avec elle et le jeu
    /// n'est pas lance. A n'employer qu'avec un Cidre qui connait `--json` ici
    /// (`LaunchOptions.updateBeforeLaunch` non nul) : un plus ancien laisserait
    /// le jeu ecrire dans un tube que Verger ferme en quittant.
    public func play(
        id: String, log: URL? = nil, skipUpdate: Bool = false, acceptCloudLoss: Bool = false,
        onEvent: @escaping @Sendable (PlayEvent) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [executable.path, "play", id, "--json"] + (skipUpdate ? ["--sans-maj"] : [])
            + (acceptCloudLoss ? ["--accord-nuage"] : [])
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        // Le journal : ce que Cidre, SteamCMD puis le lanceur ecrivent a l'erreur.
        var logHandle: FileHandle?
        if let log {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: log)
        }
        defer { try? logHandle?.close() }
        process.standardError = logHandle ?? FileHandle.nullDevice

        // La sortie standard : des evenements, un objet JSON par ligne. Toute
        // autre ligne rejoint le journal.
        let pipe = Pipe()
        process.standardOutput = pipe
        let lines = LineBuffer()
        let sink = logHandle
        let deliver: @Sendable (String) -> Void = { line in
            if let event = PlayEvent.parse(line: line) {
                onEvent(event)
            } else if let sink, !line.isEmpty {
                _ = try? sink.seekToEnd()
                try? sink.write(contentsOf: Data((line + "\n").utf8))
            }
        }
        let reader = PipeReader(pipe) { data in
            for line in lines.append(data) { deliver(line) }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        reader.finish()
        if let rest = lines.flush() { deliver(rest) }

        try Task.checkCancellation()
        // code 4 : une mise a jour de ce jeu tourne deja (autre commande)
        if process.terminationStatus == 4 { throw CidreError.updateRunning }
        // code 7 : des sauvegardes que Steam croit ici manquent (la garde le dit au journal)
        if process.terminationStatus == 7 { throw CidreError.cloudSavesAtRisk(files: Self.cloudGuardFiles(in: log)) }
        guard process.terminationStatus == 0 else {
            throw CidreError.commandFailed(
                command: "play \(id)", status: process.terminationStatus,
                message: log.map { L10n.format("voir %@", $0.path) } ?? "")
        }
    }

    // MARK: Options de lancement

    /// `cidre set <id> <option> <valeur>` : regle une option pour ce jeu, dans
    /// le profils.toml de l'utilisateur. S'applique au prochain lancement.
    public func setOption(id: String, _ key: LaunchOptions.Key, to value: Bool) async throws {
        _ = try await checked(["set", id, key.rawValue, value ? "true" : "false"])
    }

    public func setOption(id: String, _ key: LaunchOptions.Key, to value: String) async throws {
        _ = try await checked(["set", id, key.rawValue, value])
    }

    public func setOption(id: String, _ key: LaunchOptions.Key, to value: Int) async throws {
        _ = try await checked(["set", id, key.rawValue, String(value)])
    }

    /// `cidre unset <id> [option]` : revient au reglage livre par Cidre, pour
    /// une option ou (sans `key`) pour toutes celles du jeu.
    public func resetOptions(id: String, _ key: LaunchOptions.Key? = nil) async throws {
        _ = try await checked(["unset", id] + (key.map { [$0.rawValue] } ?? []))
    }

    /// L'identifiant qui designe les reglages generaux dans `cidre set` / `cidre unset`.
    public static let defaultsID = "defaut"

    /// `cidre options --json` : les reglages generaux.
    public func defaultOptions() async throws -> DefaultOptions {
        try await json(["options", "--json"])
    }

    // MARK: Steam

    /// `cidre session --json` : le compte, et si sa session est memorisee.
    public func session() async throws -> SteamSession {
        try await json(["session", "--json"])
    }

    /// `cidre logout` : oublie la session Steam. Les jeux installes restent jouables.
    public func logout() async throws {
        _ = try await checked(["logout"])
    }

    /// `cidre library --json` : les jeux que possede le compte, installes ou non.
    /// `refresh` redemande les licences a Steam au lieu de lire le cache.
    public func library(refresh: Bool = false) async throws -> [OwnedGame] {
        do {
            return try await json(["library", "--json"] + (refresh ? ["--refresh"] : []))
        } catch let CidreError.commandFailed(_, status, _) where status == 3 {
            throw CidreError.steamSessionMissing
        }
    }

    /// `cidre updates --json` : pour chaque jeu Steam installe, son build face au
    /// dernier publie. Information publique, lue sans compte.
    public func updates(refresh: Bool = false) async throws -> [GameUpdate] {
        try await json(["updates", "--json"] + (refresh ? ["--refresh"] : []))
    }

    /// `cidre updates --fond` : Cidre rafraichit en arriere-plan ce qu'il sait
    /// des builds publies (si c'est perime) et rend la main aussitot ; le premier
    /// « Jouer » n'aura pas a attendre Steam. Un Cidre d'avant ne connait pas
    /// l'option : il fait la meme demande, en attendant -- sans gravite ici.
    public func refreshUpdatesInBackground() async {
        _ = try? await run(["updates", "--fond"])
    }

    /// `cidre dl <appid> <platform>` : telecharge (ou met a jour) le jeu dans le dossier Cidre,
    /// en rapportant l'avancement. Annuler la tache arrete le telechargement
    /// (SteamCMD le reprendra ou il en etait).
    /// `cidre import <appid> --json` : reprend un jeu deja installe par CrossOver,
    /// Whisky ou Heroic (clone APFS, bouteille intacte), et ramene ses
    /// sauvegardes de la bouteille. Un refus (code 1) porte son message sur
    /// l'erreur standard, montre tel quel.
    @discardableResult
    public func importGame(appid: Int) async throws -> ImportResult {
        let result = try await checked(["import", String(appid), "--json"])
        // le jeu est repris : une sortie illisible ne doit pas en faire un echec
        return (try? JSONDecoder().decode(ImportResult.self, from: result.stdout)) ?? ImportResult()
    }

    public func download(
        appid: Int, platform: String = "windows",
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        // SteamCMD ne rend sa sortie ligne a ligne que sur un terminal : on lui
        // en prete un par `script`, sinon l'avancement arrive par blocs de 4 Kio.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/sh", executable.path, "dl", String(appid), platform]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let tail = TextTail()
        let reader = PipeReader(pipe) { data in
            let chunk = String(decoding: data, as: UTF8.self)
            tail.append(chunk)
            if let progress = DownloadProgress.last(in: chunk) { onProgress(progress) }
            // Sans session memorisee, SteamCMD attendrait un mot de passe que
            // personne ne tapera : on arrete, et on le dit.
            if chunk.range(of: "password:", options: .caseInsensitive) != nil {
                tail.markPasswordPrompt()
                process.terminate()
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        // la fin de la sortie : le dernier avancement, ou le message d'erreur
        reader.finish()

        // code 3 : Cidre n'a pas de session Steam memorisee
        if tail.sawPasswordPrompt || process.terminationStatus == 3 { throw CidreError.steamSessionMissing }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw CidreError.commandFailed(
                command: "dl \(appid)", status: process.terminationStatus, message: tail.lastLines(4))
        }
    }

    // MARK: Hors Steam

    /// `cidre add <exe> [nom] --json` : ajoute un jeu Windows a la bibliotheque.
    public func add(executable exe: URL, name: String? = nil) async throws -> Game {
        var arguments = ["add", exe.path]
        if let name, !name.isEmpty { arguments.append(name) }
        return try await json(arguments + ["--json"])
    }

    /// `cidre run <exe>` : lance un .exe une fois (un installeur), sans l'ajouter.
    public func runExecutable(_ exe: URL, log: URL? = nil) async throws {
        try await runLogged(["run", exe.path], log: log)
    }

    /// `cidre prefix` : le disque C: du prefixe, la ou les installeurs deposent les jeux.
    public func prefix() async throws -> URL {
        let result = try await checked(["prefix"])
        let path = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// `cidre rm <id>` : retire un jeu hors Steam (ses fichiers restent), ou
    /// desinstalle un jeu du dossier Cidre (ses fichiers sont supprimes).
    public func remove(id: String) async throws {
        _ = try await checked(["rm", id])
    }

    // MARK: Plomberie

    func json<T: Decodable>(_ arguments: [String]) async throws -> T {
        let result = try await checked(arguments)
        do {
            return try JSONDecoder().decode(T.self, from: result.stdout)
        } catch {
            throw CidreError.invalidOutput(command: arguments.joined(separator: " "), underlying: "\(error)")
        }
    }

    /// Lance la commande et exige un code de retour nul.
    func checked(_ arguments: [String]) async throws -> RunResult {
        let result = try await run(arguments)
        guard result.status == 0 else {
            throw CidreError.commandFailed(
                command: arguments.joined(separator: " "), status: result.status,
                message: String(decoding: result.stderr, as: UTF8.self))
        }
        return result
    }

    func runLogged(_ arguments: [String], log: URL?) async throws {
        let result = try await run(arguments, output: log)
        guard result.status == 0 else {
            throw CidreError.commandFailed(
                command: arguments.joined(separator: " "), status: result.status,
                message: log.map { L10n.format("voir %@", $0.path) } ?? "")
        }
    }

    struct RunResult: Sendable {
        var status: Int32
        var stdout = Data()
        var stderr = Data()
    }

    /// Lance `sh cidre <arguments>` hors du fil principal. Sans `output`, capture
    /// stdout et stderr ; avec, les redirige tous deux vers ce fichier.
    func run(_ arguments: [String], output: URL? = nil) async throws -> RunResult {
        let executable = executable
        let environment = environment
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    // `cidre` est un script sh : on passe par /bin/sh pour ne pas
                    // dependre de son bit d'execution.
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = [executable.path] + arguments
                    process.environment = environment
                    process.standardInput = FileHandle.nullDevice

                    if let output {
                        try FileManager.default.createDirectory(
                            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                        FileManager.default.createFile(atPath: output.path, contents: nil)
                        let handle = try FileHandle(forWritingTo: output)
                        process.standardOutput = handle
                        process.standardError = handle
                        try process.run()
                        process.waitUntilExit()
                        try? handle.close()
                        continuation.resume(returning: RunResult(status: process.terminationStatus))
                        return
                    }

                    let out = Pipe(), err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    try process.run()
                    // Lire les deux tubes en parallele : un tube plein (64 Kio)
                    // bloquerait la commande, et nous avec.
                    let stderrBox = DataBox()
                    let reading = DispatchGroup()
                    DispatchQueue.global(qos: .userInitiated).async(group: reading) {
                        stderrBox.set(err.fileHandleForReading.readDataToEndOfFile())
                    }
                    let stdout = out.fileHandleForReading.readDataToEndOfFile()
                    reading.wait()
                    process.waitUntilExit()
                    continuation.resume(returning: RunResult(
                        status: process.terminationStatus, stdout: stdout, stderr: stderrBox.get()))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Une valeur partagee entre deux files, sous verrou.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// Decoupe en lignes une sortie qui arrive par morceaux.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    /// Les lignes completes que ce morceau termine.
    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    /// Ce qui reste a la fin, sans retour a la ligne.
    func flush() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}

/// La fin de la sortie d'une commande longue, pour l'afficher si elle echoue.
private final class TextTail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var passwordPrompt = false

    func append(_ chunk: String) {
        lock.lock(); defer { lock.unlock() }
        text = String((text + chunk).suffix(4000))
    }

    func markPasswordPrompt() { lock.lock(); passwordPrompt = true; lock.unlock() }
    var sawPasswordPrompt: Bool { lock.lock(); defer { lock.unlock() }; return passwordPrompt }

    func lastLines(_ count: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(count)
            .joined(separator: "\n")
    }
}
