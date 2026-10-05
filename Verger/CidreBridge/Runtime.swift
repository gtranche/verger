import Foundation

/// L'etat du runtime Cidre installe (`cidre status --json`).
public struct RuntimeStatus: Decodable, Equatable, Sendable {
    /// La version livree, ou "dev" pour un depot de developpement.
    public let version: String
    public let root: String
    /// Les binaires du runtime sont la.
    public let runtimePresent: Bool
    /// Le prefixe Wine a ete cree (`cidre setup` est passe).
    public let prefixReady: Bool
    public let steamcmdPresent: Bool
    /// Le compte que Cidre utiliserait : celui du client Steam, ou `CIDRE_STEAM_USER`.
    public let steamAccount: String?
    /// Un jeu tourne par Cidre : pas le moment de mettre a jour.
    public let gameRunning: Bool
    public let prerequisites: Prerequisites

    /// Bibliotheques Homebrew que la pile charge par leur chemin.
    public struct Prerequisites: Decodable, Equatable, Sendable {
        public let spirvTools: Bool
        public let freetype: Bool

        enum CodingKeys: String, CodingKey {
            case spirvTools = "spirv_tools"
            case freetype
        }

        /// Les paquets Homebrew qui manquent.
        public var missing: [String] {
            (spirvTools ? [] : ["spirv-tools"]) + (freetype ? [] : ["freetype"])
        }
    }

    public var isDevelopmentCheckout: Bool { version == "dev" }

    enum CodingKeys: String, CodingKey {
        case version
        case root = "racine"
        case runtimePresent = "runtime"
        case prefixReady = "prefixe"
        case steamcmdPresent = "steamcmd"
        case steamAccount = "compte_steam"
        case gameRunning = "jeu_en_cours"
        case prerequisites = "prerequis"
    }
}

extension CidreCLI {
    /// `cidre status --json`
    public func status() async throws -> RuntimeStatus {
        try await json(["status", "--json"])
    }
}

/// Une version publiee du runtime Cidre.
public struct RuntimeRelease: Equatable, Sendable {
    public let version: String
    /// L'archive `cidre-runtime.tar.xz` (xz : macOS la decompresse sans rien installer).
    public let archive: URL
    public let sizeBytes: Int64

    public init(version: String, archive: URL, sizeBytes: Int64 = 0) {
        self.version = version
        self.archive = archive
        self.sizeBytes = sizeBytes
    }

    /// Cette release est-elle plus recente que la version installee ?
    public func isNewer(than installed: String) -> Bool {
        Self.compare(version, installed) == .orderedDescending
    }

    /// Compare deux versions « 1.10.2 » champ par champ (un « v » initial est ignore).
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func fields(_ s: String) -> [Int] {
            s.drop { !$0.isNumber }.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let (x, y) = (fields(a), fields(b))
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

public enum RuntimeError: Error, LocalizedError, Sendable {
    case noArchiveInRelease(String)
    case downloadFailed(String)
    case extractionFailed(String)
    case setupFailed(String)
    case invalidArchive

    public var errorDescription: String? {
        switch self {
        case let .noArchiveInRelease(version):
            L10n.format("La version %@ de Cidre ne contient pas d'archive installable par Verger (cidre-runtime.tar.xz).", version)
        case let .downloadFailed(detail): L10n.format("Le téléchargement de Cidre a échoué : %@", detail)
        case let .extractionFailed(detail): L10n.format("La décompression de Cidre a échoué : %@", detail)
        case let .setupFailed(detail): L10n.format("La configuration de Cidre a échoué : %@", detail)
        case .invalidArchive: L10n.string("L'archive ne contient pas Cidre.")
        }
    }
}

/// Installe et met a jour le runtime Cidre : Verger telecharge l'archive de la
/// derniere release, la decompresse, puis laisse le runtime se configurer
/// lui-meme (`cidre setup`). Verger ne contient aucun binaire du runtime.
public struct RuntimeInstaller: Sendable {
    public enum Step: Equatable, Sendable {
        case downloading(doneBytes: Int64, totalBytes: Int64)
        case extracting
        /// Une etape de `cidre setup`, telle qu'il l'annonce (« 2/6 Prefixe Wine »).
        case configuring(String)
    }

    public static let assetName = "cidre-runtime.tar.xz"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/gtranche/cidre/releases/latest")!

    /// Le dossier qui recoit `cidre/` : ~/Library/Application Support/Cidre.
    /// C'est aussi la que vivent les jeux telecharges et profils.toml, qu'une
    /// mise a jour ne touche pas.
    public let home: URL

    public init(home: URL = RuntimeInstaller.defaultHome()) {
        self.home = home
    }

    /// ~/Library/Application Support/Cidre, ou `VERGER_CIDRE_HOME` (pour
    /// essayer une installation sans toucher a celle en place).
    public static func defaultHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment["VERGER_CIDRE_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return userHome.appendingPathComponent("Library/Application Support/Cidre")
    }

    /// La CLI du runtime que ce dossier contient, s'il y en a un.
    public var installedCLI: CidreCLI? {
        let url = home.appendingPathComponent("cidre/cidre")
        return FileManager.default.fileExists(atPath: url.path) ? CidreCLI(executable: url) : nil
    }

    /// La derniere release publiee. `VERGER_RUNTIME_URL` la remplace par une
    /// archive donnee (un fichier local, un miroir) : pour installer hors ligne
    /// ou essayer une version avant de la publier.
    public static func latestRelease(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        api: URL = latestReleaseAPI
    ) async throws -> RuntimeRelease {
        if let override = environment["VERGER_RUNTIME_URL"], !override.isEmpty,
           let url = override.contains("://") ? URL(string: override) : URL(fileURLWithPath: override) {
            return RuntimeRelease(version: environment["VERGER_RUNTIME_VERSION"] ?? "0", archive: url)
        }
        var request = URLRequest(url: api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RuntimeError.downloadFailed(L10n.format("GitHub a répondu %lld.", (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        return try parseRelease(data)
    }

    static func parseRelease(_ data: Data) throws -> RuntimeRelease {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let size: Int64
                let browser_download_url: URL
            }
            let tag_name: String
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = String(release.tag_name.drop { !$0.isNumber })
        guard let asset = release.assets.first(where: { $0.name == assetName }) else {
            throw RuntimeError.noArchiveInRelease(version)
        }
        return RuntimeRelease(version: version, archive: asset.browser_download_url, sizeBytes: asset.size)
    }

    /// Installe (ou met a jour) le runtime et rend sa CLI. Une mise a jour
    /// decompresse par-dessus l'installation : le prefixe Wine, donc les
    /// sauvegardes, n'est pas dans l'archive et reste en place.
    public func install(
        _ release: RuntimeRelease, onStep: @escaping @Sendable (Step) -> Void
    ) async throws -> CidreCLI {
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)

        // 1. l'archive
        onStep(.downloading(doneBytes: 0, totalBytes: release.sizeBytes))
        let archive: URL
        var downloaded: URL?
        if release.archive.isFileURL {
            archive = release.archive
        } else {
            let file = try await Downloader.download(release.archive) { done, total in
                onStep(.downloading(doneBytes: done, totalBytes: total > 0 ? total : release.sizeBytes))
            }
            archive = file
            downloaded = file
        }
        defer { if let downloaded { try? fm.removeItem(at: downloaded) } }
        try Task.checkCancellation()

        // 2. decompression (tar lit le xz tout seul)
        onStep(.extracting)
        let tar = try await Self.run("/usr/bin/tar", ["-xf", archive.path, "-C", home.path])
        guard tar.status == 0 else { throw RuntimeError.extractionFailed(tar.lastLines) }
        guard let cli = installedCLI else { throw RuntimeError.invalidArchive }
        try Task.checkCancellation()

        // 3. le runtime se configure lui-meme
        try await Self.configure(cli, onStep: onStep)
        return cli
    }

    /// `cidre setup` : (re)configure un runtime en place, en annoncant ses etapes.
    public static func configure(
        _ cli: CidreCLI, onStep: @escaping @Sendable (Step) -> Void
    ) async throws {
        onStep(.configuring(L10n.string("Préparation")))
        let setup = try await run("/bin/sh", [cli.executable.path, "setup"]) { line in
            // `== 2/6 Prefixe Wine ==`
            if line.hasPrefix("== "), line.hasSuffix(" ==") {
                onStep(.configuring(String(line.dropFirst(3).dropLast(3))))
            }
        }
        guard setup.status == 0 else { throw RuntimeError.setupFailed(setup.lastLines) }
    }

    // MARK: Plomberie

    struct Outcome: Sendable {
        let status: Int32
        let lastLines: String
    }

    /// Lance une commande longue en lisant sa sortie ligne a ligne. Annuler la
    /// tache arrete la commande.
    static func run(
        _ executable: String, _ arguments: [String],
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let lines = LineBuffer(onLine: onLine)
        let reader = PipeReader(pipe) { lines.append(String(decoding: $0, as: UTF8.self)) }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        reader.finish()
        try Task.checkCancellation()
        return Outcome(status: process.terminationStatus, lastLines: lines.tail(5))
    }
}

/// Decoupe une sortie en lignes au fil de l'eau, et en garde la fin.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var recent: [String] = []
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func append(_ chunk: String) {
        lock.lock()
        pending += chunk
        var complete: [String] = []
        while let end = pending.firstIndex(where: \.isNewline) {
            complete.append(String(pending[..<end]).trimmingCharacters(in: .whitespaces))
            pending = String(pending[pending.index(after: end)...])
        }
        recent = Array((recent + complete.filter { !$0.isEmpty }).suffix(20))
        lock.unlock()
        complete.forEach(onLine)
    }

    func tail(_ count: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        return (recent + (rest.isEmpty ? [] : [rest])).suffix(count).joined(separator: "\n")
    }
}

/// Telecharge un fichier en rapportant l'avancement ; rend le fichier temporaire.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private let lock = NSLock()

    private let suffix: String

    private init(suffix: String, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.suffix = suffix
        self.onProgress = onProgress
    }

    static func download(_ url: URL, suffix: String = ".tar.xz", onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let delegate = Downloader(suffix: suffix, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.lock.lock()
                delegate.continuation = continuation
                delegate.lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(RuntimeError.downloadFailed(L10n.format("le serveur a répondu %lld", http.statusCode))))
            return
        }
        // Le fichier disparait au retour de cette methode : on le met de cote.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("verger-\(UUID().uuidString)\(suffix)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as? URLError)?.code == .cancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(RuntimeError.downloadFailed(error.localizedDescription)))
        }
    }
}
