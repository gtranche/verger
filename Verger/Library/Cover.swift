import SwiftUI

/// La vignette d'un jeu, au format portrait de la bibliotheque Steam.
///
/// On cherche, dans l'ordre : la jaquette portrait que le client Steam a deja
/// en cache, celle du CDN de Steam, puis l'image d'en-tete (paysage) du jeu,
/// en cache puis sur le CDN. Tous les jeux n'ont pas de jaquette portrait, et
/// certains (outils, jeux hors Steam) n'ont aucune image : il reste alors un
/// carton au nom du jeu.
struct Cover: View {
    /// `nil` pour un jeu hors Steam : pas d'image, un carton a son nom.
    let appid: Int?
    let name: String

    @State private var art: Art?

    var body: some View {
        ZStack {
            switch art {
            case let .portrait(image):
                Image(nsImage: image).resizable()
            case let .landscape(image):
                // Une image paysage dans un cadre portrait : entiere au centre,
                // sur elle-meme agrandie et floutee pour remplir le cadre.
                Image(nsImage: image).resizable().scaledToFill()
                    .blur(radius: 18)
                    .overlay(.black.opacity(0.35))
                Image(nsImage: image).resizable().scaledToFit()
            case nil:
                placeholder
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: appid) {
            art = await Self.art(for: appid)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.15)],
                startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
        }
    }

    // MARK: Recherche de l'image

    enum Art {
        case portrait(NSImage)
        case landscape(NSImage)
    }

    /// Ce qu'on a deja trouve, pour ne pas relire le disque ni le reseau a
    /// chaque passage d'une carte a l'ecran. `nil` = cherche, rien trouve.
    @MainActor private static var found: [Int: Art?] = [:]

    @MainActor
    static func art(for appid: Int?) async -> Art? {
        guard let appid else { return nil }
        if let known = found[appid] { return known }
        var art: Art?
        if let image = cached(appid: appid, names: ["library_600x900.jpg", "library_capsule.jpg"]) {
            art = .portrait(image)
        } else if let image = await remote(appid: appid, name: "library_600x900.jpg") {
            art = .portrait(image)
        } else if let image = cached(appid: appid, names: ["header.jpg", "library_header.jpg"]) {
            art = .landscape(image)
        } else if let image = await remote(appid: appid, name: "header.jpg") {
            art = .landscape(image)
        }
        found[appid] = art
        return art
    }

    private static let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/appcache/librarycache")

    /// Le client range ses images soit a la racine du dossier de l'appid, soit
    /// dans un sous-dossier nomme par un hash.
    static func cachedFile(appid: Int, names: [String]) -> URL? {
        let fm = FileManager.default
        let dir = cacheDirectory.appendingPathComponent(String(appid))
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

    private static func cached(appid: Int, names: [String]) -> NSImage? {
        cachedFile(appid: appid, names: names).flatMap(NSImage.init(contentsOf:))
    }

    @MainActor
    private static func remote(appid: Int, name: String) async -> NSImage? {
        guard let url = URL(string: "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(appid)/\(name)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return NSImage(data: data)
    }
}
