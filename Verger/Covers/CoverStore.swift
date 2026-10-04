import AppKit
import Observation

/// Les jaquettes choisies par l'utilisateur, qui passent avant celles de Steam :
/// pour habiller un jeu non-Steam, ou remplacer une image qui ne plait pas.
/// Rangees dans ~/Library/Application Support/Verger/jaquettes, une par jeu.
@MainActor
@Observable
final class CoverStore {
    static let shared = CoverStore()

    /// Change a chaque jaquette posee ou retiree : les vignettes se rechargent.
    private(set) var revision = 0

    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Verger/jaquettes")

    private static let extensions = ["png", "jpg", "jpeg", "webp"]

    /// La jaquette posee par l'utilisateur pour ce jeu, s'il y en a une.
    func customCover(for id: String) -> URL? {
        Self.extensions
            .map { directory.appendingPathComponent("\(id).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Pose une image comme jaquette du jeu. Refuse ce qui n'est pas une image.
    func setCover(for id: String, data: Data, fileExtension: String) throws {
        guard NSImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let ext = Self.extensions.contains(fileExtension.lowercased()) ? fileExtension.lowercased() : "png"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeFiles(for: id)
        try data.write(to: directory.appendingPathComponent("\(id).\(ext)"), options: .atomic)
        revision += 1
    }

    func setCover(for id: String, from file: URL) throws {
        try setCover(for: id, data: Data(contentsOf: file), fileExtension: file.pathExtension)
    }

    /// Retire la jaquette posee : le jeu retrouve celle de Steam, ou son carton.
    func removeCover(for id: String) {
        removeFiles(for: id)
        revision += 1
    }

    private func removeFiles(for id: String) {
        for ext in Self.extensions {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).\(ext)"))
        }
    }
}
