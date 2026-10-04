import SwiftUI

/// La jaquette d'un jeu (format portrait 600x900 de la bibliotheque Steam).
/// On prend d'abord celle que le client Steam a deja en cache sur le disque ;
/// a defaut, celle du CDN de Steam ; a defaut, un carton au nom du jeu.
struct Cover: View {
    let appid: Int
    let name: String

    var body: some View {
        Group {
            if let local = Self.cachedCover(appid: appid), let image = NSImage(contentsOf: local) {
                Image(nsImage: image).resizable()
            } else {
                AsyncImage(url: Self.cdnCover(appid: appid)) { phase in
                    if let image = phase.image {
                        image.resizable()
                    } else {
                        placeholder
                    }
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Text(name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    private static let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/appcache/librarycache")

    /// Le client range la jaquette soit a la racine du dossier de l'appid, soit
    /// dans un sous-dossier nomme par un hash, sous l'un de ces deux noms.
    static func cachedCover(appid: Int) -> URL? {
        let fm = FileManager.default
        let dir = cacheDirectory.appendingPathComponent(String(appid))
        let names = ["library_600x900.jpg", "library_capsule.jpg"]
        let subdirectories = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.hasDirectoryPath } ?? []
        for folder in [dir] + subdirectories {
            for name in names {
                let url = folder.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    static func cdnCover(appid: Int) -> URL? {
        URL(string: "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(appid)/library_600x900.jpg")
    }
}
