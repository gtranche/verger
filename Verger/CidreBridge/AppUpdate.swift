import Foundation

/// Une version publiee de Verger (une release GitHub portant `Verger.zip`).
public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let archive: URL
    public let sizeBytes: Int64

    public init(version: String, archive: URL, sizeBytes: Int64 = 0) {
        self.version = version
        self.archive = archive
        self.sizeBytes = sizeBytes
    }

    public func isNewer(than installed: String) -> Bool {
        RuntimeRelease.compare(version, installed) == .orderedDescending
    }
}

public enum AppUpdateError: Error, LocalizedError, Sendable {
    case checkFailed(String)
    case noArchiveInRelease(String)
    case invalidArchive(String)
    case notReplaceable(String)

    public var errorDescription: String? {
        switch self {
        case let .checkFailed(detail): L10n.format("Impossible de vérifier les mises à jour de Verger : %@", detail)
        case let .noArchiveInRelease(version): L10n.format("La version %@ de Verger ne contient pas d'archive Verger.zip.", version)
        case let .invalidArchive(detail): L10n.format("L'archive de mise à jour n'est pas valide : %@", detail)
        case let .notReplaceable(detail): L10n.format("Verger ne peut pas se remplacer lui-même : %@", detail)
        }
    }
}

/// La mise a jour de Verger par ses releases GitHub : on telecharge `Verger.zip`,
/// on verifie ce qu'il contient, et on le met a la place de l'application.
/// Independant du runtime : mettre Verger a jour ne retelecharge rien de Cidre.
public enum AppUpdater {
    public static let assetName = "Verger.zip"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/gtranche/verger/releases/latest")!

    public static func latestRelease(api: URL = latestReleaseAPI) async throws -> AppRelease {
        var request = URLRequest(url: api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 404 : le depot n'a encore aucune release
        guard status != 404 else { throw AppUpdateError.checkFailed(L10n.string("aucune version n'est encore publiée.")) }
        guard status == 200 else { throw AppUpdateError.checkFailed(L10n.format("GitHub a répondu %lld.", status)) }
        return try parseRelease(data)
    }

    static func parseRelease(_ data: Data) throws -> AppRelease {
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
            throw AppUpdateError.noArchiveInRelease(version)
        }
        return AppRelease(version: version, archive: asset.browser_download_url, sizeBytes: asset.size)
    }

    /// Telecharge la release et la met a la place de `app`. L'application en
    /// cours continue de tourner sur l'ancienne version jusqu'a sa relance.
    public static func install(
        _ release: AppRelease, replacing app: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        let fm = FileManager.default
        guard app.pathExtension == "app" else {
            throw AppUpdateError.notReplaceable(L10n.string("il n'est pas lancé depuis une application (.app)."))
        }
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            throw AppUpdateError.notReplaceable(L10n.format("le dossier %@ n'est pas modifiable.", app.deletingLastPathComponent().path))
        }

        let archive: URL
        var downloaded: URL?
        if release.archive.isFileURL {
            archive = release.archive
        } else {
            let file = try await Downloader.download(release.archive, suffix: ".zip", onProgress: onProgress)
            archive = file
            downloaded = file
        }
        defer { if let downloaded { try? fm.removeItem(at: downloaded) } }

        let work = fm.temporaryDirectory.appendingPathComponent("verger-maj-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let unzip = try await RuntimeInstaller.run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
        guard unzip.status == 0 else { throw AppUpdateError.invalidArchive(unzip.lastLines) }
        let fresh = work.appendingPathComponent(app.lastPathComponent)
        guard fm.isExecutableFile(atPath: fresh.appendingPathComponent("Contents/MacOS/Verger").path) else {
            throw AppUpdateError.invalidArchive(L10n.format("pas de %@ dedans.", app.lastPathComponent))
        }
        // Une application dont la signature ne tient pas ne se lancerait pas.
        let signature = try await RuntimeInstaller.run("/usr/bin/codesign", ["--verify", "--deep", fresh.path])
        guard signature.status == 0 else { throw AppUpdateError.invalidArchive(L10n.string("signature invalide.")) }

        // On ecarte l'ancienne, on pose la nouvelle ; au moindre echec on remet l'ancienne.
        let previous = app.deletingLastPathComponent()
            .appendingPathComponent(".\(app.deletingPathExtension().lastPathComponent)-precedent.app")
        try? fm.removeItem(at: previous)
        try fm.moveItem(at: app, to: previous)
        do {
            try fm.moveItem(at: fresh, to: app)
        } catch {
            try? fm.moveItem(at: previous, to: app)
            throw AppUpdateError.notReplaceable(error.localizedDescription)
        }
        try? fm.removeItem(at: previous)
    }
}
