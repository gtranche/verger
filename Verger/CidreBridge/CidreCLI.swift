import Foundation

public enum CidreError: Error, LocalizedError, Sendable, Equatable {
    /// La commande a rendu un code non nul ; `message` porte sa sortie d'erreur.
    case commandFailed(command: String, status: Int32, message: String)
    /// La sortie n'est pas le JSON attendu (CLI trop ancienne, sans `--json` ?).
    case invalidOutput(command: String, underlying: String)
    /// SteamCMD n'a pas de session memorisee : il faut se connecter (`cidre login`).
    case steamSessionMissing

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`cidre \(command)` a échoué (code \(status))" + (detail.isEmpty ? "." : " : \(detail)")
        case let .invalidOutput(command, underlying):
            return "Sortie de `cidre \(command)` illisible — Cidre est-il à jour ? (\(underlying))"
        case .steamSessionMissing:
            return "La session Steam n'est pas mémorisée : connecte-toi (bouton +, « Connexion à Steam… »)."
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

    /// `cidre play <id>`. Rend la main quand la commande se termine : tout de
    /// suite pour un jeu lance par Steam, a la sortie du jeu sinon. La sortie
    /// de la commande va dans `log`.
    public func play(id: String, log: URL? = nil) async throws {
        try await runLogged(["play", id], log: log)
    }

    // MARK: Options de lancement

    /// `cidre set <id> <option> <valeur>` : regle une option pour ce jeu, dans
    /// le profils.toml de l'utilisateur. S'applique au prochain lancement.
    public func setOption(id: String, _ key: LaunchOptions.Key, to value: Bool) async throws {
        _ = try await checked(["set", id, key.rawValue, value ? "true" : "false"])
    }

    public func setOption(id: String, _ key: LaunchOptions.Key, to value: Int) async throws {
        _ = try await checked(["set", id, key.rawValue, String(value)])
    }

    /// `cidre unset <id> [option]` : revient au reglage livre par Cidre, pour
    /// une option ou (sans `key`) pour toutes celles du jeu.
    public func resetOptions(id: String, _ key: LaunchOptions.Key? = nil) async throws {
        _ = try await checked(["unset", id] + (key.map { [$0.rawValue] } ?? []))
    }

    // MARK: Steam

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

    /// `cidre dl <appid> <platform>` : telecharge (ou met a jour) le jeu dans le dossier Cidre,
    /// en rapportant l'avancement. Annuler la tache arrete le telechargement
    /// (SteamCMD le reprendra ou il en etait).
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
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
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
                message: log.map { "voir \($0.path)" } ?? "")
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
