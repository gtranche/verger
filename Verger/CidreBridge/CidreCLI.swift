import Foundation

public enum CidreError: Error, LocalizedError, Sendable {
    /// La commande a rendu un code non nul ; `message` porte sa sortie d'erreur.
    case commandFailed(command: String, status: Int32, message: String)
    /// La sortie n'est pas le JSON attendu (CLI trop ancienne, sans `--json` ?).
    case invalidOutput(command: String, underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`cidre \(command)` a échoué (code \(status))" + (detail.isEmpty ? "." : " : \(detail)")
        case let .invalidOutput(command, underlying):
            return "Sortie de `cidre \(command)` illisible — Cidre est-il à jour ? (\(underlying))"
        }
    }
}

/// La CLI `cidre` : la seule frontiere entre Verger et le runtime.
/// Verger ne reimplemente rien, il appelle ces commandes et lit leur JSON.
public struct CidreCLI: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    // MARK: Detection

    /// Emplacements ou chercher la CLI, du plus explicite au plus general :
    /// le choix de l'utilisateur, `VERGER_CIDRE`, l'install standard de
    /// `installer_cidre.sh`, puis le PATH.
    public static func candidates(
        userChoice: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var paths: [String] = []
        if let userChoice, !userChoice.isEmpty { paths.append(userChoice) }
        if let env = environment["VERGER_CIDRE"], !env.isEmpty { paths.append(env) }
        paths.append(home.appendingPathComponent("Library/Application Support/Cidre/cidre/cidre").path)
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

    // MARK: Commandes

    /// `cidre list --json`
    public func list() async throws -> [Game] {
        try await json(["list", "--json"])
    }

    /// `cidre info <appid> --json`
    public func info(appid: Int) async throws -> GameInfo {
        try await json(["info", String(appid), "--json"])
    }

    /// `cidre play <appid>`. Rend la main quand la commande se termine : tout de
    /// suite pour un jeu lance par Steam, a la sortie du jeu pour un jeu du
    /// dossier Cidre. La sortie de la commande va dans `log`.
    public func play(appid: Int, log: URL? = nil) async throws {
        let result = try await run(["play", String(appid)], output: log)
        guard result.status == 0 else {
            throw CidreError.commandFailed(
                command: "play \(appid)", status: result.status,
                message: log.map { "voir \($0.path)" } ?? "")
        }
    }

    // MARK: Plomberie

    func json<T: Decodable>(_ arguments: [String]) async throws -> T {
        let command = arguments.joined(separator: " ")
        let result = try await run(arguments)
        guard result.status == 0 else {
            throw CidreError.commandFailed(
                command: command, status: result.status,
                message: String(decoding: result.stderr, as: UTF8.self))
        }
        do {
            return try JSONDecoder().decode(T.self, from: result.stdout)
        } catch {
            throw CidreError.invalidOutput(command: command, underlying: "\(error)")
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
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    // `cidre` est un script sh : on passe par /bin/sh pour ne pas
                    // dependre de son bit d'execution.
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = [executable.path] + arguments
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
