import Foundation

/// Une connexion a Steam par SteamCMD (`cidre login`), pilotee depuis une
/// fenetre : SteamCMD pose ses questions sur un terminal, on lui en prete un et
/// on y relaie ce que l'utilisateur tape. Rien n'est conserve : le mot de passe
/// passe a SteamCMD, qui memorise ensuite la session lui-meme.
public final class SteamLoginSession: @unchecked Sendable {
    public enum Event: Equatable, Sendable {
        case passwordRequested
        /// Code Steam Guard, recu par e-mail ou lu dans l'appli mobile.
        case codeRequested
        /// Steam attend qu'on valide la connexion dans l'appli mobile.
        case mobileConfirmationRequested
        case succeeded
        case failed(String)
    }

    private let cli: CidreCLI
    private let onEvent: @Sendable (Event) -> Void
    private let process = Process()
    private let input = Pipe()
    private let lock = NSLock()
    private var output = ""
    /// Jusqu'ou la sortie a deja ete interpretee.
    private var scanned = 0
    private var cancelled = false

    public init(cli: CidreCLI, onEvent: @escaping @Sendable (Event) -> Void) {
        self.cli = cli
        self.onEvent = onEvent
    }

    public func start() throws {
        // SteamCMD ne demande le mot de passe que sur un terminal : `script` lui
        // en prete un, et lui relaie ce qu'on ecrit sur son entree.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/sh", cli.executable.path, "login"]
        process.environment = cli.environment
        process.standardInput = input
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.received(String(decoding: data, as: UTF8.self))
        }
        process.terminationHandler = { [weak self] _ in self?.finished() }
        try process.run()
    }

    /// Repond a la question en cours (mot de passe, code).
    public func send(_ answer: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data((answer + "\n").utf8))
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }

    private static let prompts: [(marker: String, event: Event)] = [
        ("password:", .passwordRequested),
        ("steam guard code:", .codeRequested),
        ("two-factor code:", .codeRequested),
        ("confirm the login in the steam mobile app", .mobileConfirmationRequested),
    ]

    private func received(_ chunk: String) {
        var events: [Event] = []
        lock.lock()
        output += chunk.lowercased()
        // Les questions de SteamCMD, dans l'ordre ou elles arrivent.
        while true {
            let rest = output.dropFirst(scanned)
            let next = Self.prompts
                .compactMap { prompt in rest.range(of: prompt.marker).map { (range: $0, event: prompt.event) } }
                .min { $0.range.lowerBound < $1.range.lowerBound }
            guard let next else { break }
            scanned = output.distance(from: output.startIndex, to: next.range.upperBound)
            events.append(next.event)
        }
        lock.unlock()
        events.forEach(onEvent)
    }

    private func finished() {
        lock.lock()
        let text = output
        let wasCancelled = cancelled
        lock.unlock()
        try? input.fileHandleForWriting.close()
        guard !wasCancelled else { return }
        // « Logging in user ... to Steam Public...OK », puis « Waiting for user info...OK »
        if text.contains("waiting for user info...ok") {
            onEvent(.succeeded)
        } else {
            onEvent(.failed(Self.reason(in: text)))
        }
    }

    /// La raison que donne SteamCMD : « FAILED (Invalid Password) », « ERROR (Rate Limit Exceeded) ».
    /// On ne rend jamais la sortie brute : elle peut porter ce que l'utilisateur a tape.
    static func reason(in output: String) -> String {
        guard let match = output.firstMatch(of: /(?:failed|error) \(([^)]+)\)/) else {
            return L10n.string("Steam a refusé la connexion.")
        }
        switch match.1 {
        case "invalid password": return L10n.string("Identifiant ou mot de passe incorrect.")
        case "rate limit exceeded": return L10n.string("Trop de tentatives : Steam demande de patienter avant de réessayer.")
        case "two-factor code mismatch", "invalid login auth code": return L10n.string("Code Steam Guard incorrect.")
        default: return L10n.format("Steam a refusé la connexion (%@).", String(match.1))
        }
    }
}
