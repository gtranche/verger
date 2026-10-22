import CidreBridge
import SwiftUI

/// Réglages → Stockage : les disques ou vivent les jeux, comme sur une
/// console -- ce Mac, puis chaque disque externe branche ; celui ou vont les
/// nouveaux jeux. Les emplacements Cidre eux-memes (dossiers ajoutes a la main,
/// retirer, trouves sur un disque) sont dans « Avancé ».
struct StorageSettings: View {
    @Environment(LibraryModel.self) private var library
    @State private var removing: StorageLocation?
    @State private var working = false
    @State private var showsAdvanced = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            if library.locationsSupported == false {
                Section {
                    Text("Ce Cidre ne sait ranger les jeux que sur ce Mac. Mets-le à jour pour utiliser un disque externe.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(library.disks) { disk in
                        DiskRow(disk: disk, working: $working)
                    }
                } header: {
                    HStack {
                        Text("Disques")
                        Spacer()
                        Button("Actualiser") { Task { await library.loadLocations() } }
                            .controlSize(.small)
                    }
                } footer: {
                    Text("Branche un disque externe : il apparaît ici, et dans « Déplacer vers… » et à l'installation. Cidre range ses jeux dans un dossier « Jeux Cidre » à sa racine. Quand un disque est débranché, ses jeux restent dans la bibliothèque, grisés : ils reviennent dès qu'on le rebranche.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Text("Tous les jeux d'un disque avec leur taille, et le déplacement de plusieurs jeux à la fois.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Ouvrir la page Stockage…") {
                            library.storagePageLocation = nil
                            openWindow(id: "stockage")
                        }
                    }
                }
                Section {
                    DisclosureGroup("Avancé : emplacements de Cidre", isExpanded: $showsAdvanced) {
                        advanced
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await library.loadLocations() }
        .confirmationDialog(
            Text(verbatim: L10n.format("Retirer « %@ » ?", removing?.name ?? "")),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { location in
            Button("Retirer", role: .destructive) { Task { await library.removeLocation(location) } }
        } message: { location in
            Text(verbatim: location.gameCount > 0
                ? L10n.format("Ses %@ jeux restent sur le disque, mais ne sont plus dans la bibliothèque. Pour les retrouver, ajoute-le à nouveau.", String(location.gameCount))
                : L10n.string("Cidre l'oublie ; rien n'est effacé du disque."))
        }
    }

    /// Les emplacements tels que Cidre les connait, avec leur chemin ; un
    /// dossier choisi a la main ; ceux trouves sur un disque branche.
    @ViewBuilder private var advanced: some View {
        Text("Chaque disque correspond à un emplacement de Cidre (un dossier « Jeux Cidre »). On peut aussi en ajouter un dans un dossier précis.")
            .font(.caption).foregroundStyle(.secondary)
        ForEach(library.locations) { location in
            LocationRow(location: location, removing: $removing)
        }
        HStack {
            Button("Ajouter un dossier…") { add() }
                .disabled(working)
            if working { ProgressView().controlSize(.small) }
            Spacer()
        }
        ForEach(library.detectedLocations) { found in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L10n.format("Trouvé : %@", found.volume ?? found.path))
                    Text(verbatim: found.gameCount == 1 ? L10n.format("%@ · 1 jeu", found.path) : L10n.format("%@ · %@ jeux", found.path, String(found.gameCount)))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Ajouter") {
                    working = true
                    Task {
                        await library.addLocation(URL(fileURLWithPath: found.path, isDirectory: true))
                        working = false
                    }
                }
                .disabled(working)
            }
        }
    }

    private func add() {
        guard let folder = StoragePanel.chooseFolder() else { return }
        working = true
        Task {
            await library.addLocation(folder)
            working = false
        }
    }
}

/// Un disque : son nom, sa barre, ses jeux, et s'il recoit les nouveaux jeux.
private struct DiskRow: View {
    let disk: GameDisk
    @Binding var working: Bool
    @Environment(LibraryModel.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: disk.symbol)
                .font(.title2)
                .foregroundStyle(disk.online ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: disk.name).font(.headline)
                    if !disk.online {
                        Text("Débranché")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                if let location = disk.location, let usage = library.usage(of: location) {
                    DiskUsageBar(usage: usage, height: 8, showsLegend: false)
                        .padding(.vertical, 2)
                }
                Text(verbatim: details)
                    .font(.caption).foregroundStyle(.secondary)
                if let found {
                    Button(found.gameCount == 1
                           ? L10n.string("Retrouver le jeu de Cidre qui y est")
                           : L10n.format("Retrouver les %@ jeux de Cidre qui y sont", String(found.gameCount))) {
                        working = true
                        Task {
                            _ = await library.location(for: disk)
                            working = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(working)
                }
                if let remark = disk.location?.explanation {
                    Text(verbatim: remark)
                        .font(.caption)
                        .foregroundStyle(disk.acceptsGames ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if disk.isDefault {
                    Label("Nouveaux jeux ici", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Y mettre les nouveaux jeux") {
                        working = true
                        Task {
                            await library.setDefaultDisk(disk)
                            working = false
                        }
                    }
                    .disabled(!disk.online || !disk.acceptsGames || working)
                    .help("Les jeux que tu installeras iront sur ce disque.")
                }
                if let location = disk.location {
                    Button("Jeux…") {
                        library.storagePageLocation = location.id
                        openWindow(id: "stockage")
                    }
                    .help("Ouvre la page Stockage sur ce disque : ses jeux, leur taille, et leur déplacement.")
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .opacity(disk.online ? 1 : 0.6)
    }

    /// Un emplacement Cidre deja sur ce disque, pas encore ajoute (retire, ou
    /// venu d'un autre Mac).
    private var found: DetectedLocation? {
        guard disk.isNew, let volume = disk.volume else { return nil }
        return library.detectedLocations.first { $0.path == volume.path || $0.path.hasPrefix(volume.path + "/") }
    }

    private var details: String {
        guard let location = disk.location else {
            let free = disk.freeBytes.map { L10n.format("%@ libres", L10n.bytes($0)) }
            return [free, L10n.string("aucun jeu")].compactMap { $0 }.joined(separator: " · ")
        }
        guard location.online else { return location.gamesSummary }
        var parts = [location.gamesSummary]
        if let usage = library.usage(of: location) {
            parts.insert(L10n.format("%@ libres sur %@", L10n.bytes(usage.freeBytes), L10n.bytes(usage.totalBytes)), at: 0)
        } else if let free = location.freeBytes {
            parts.insert(L10n.format("%@ libres", L10n.bytes(free)), at: 0)
        }
        if let fs = location.fileSystem, fs != "apfs" { parts.append(LocationRow.fileSystemName(fs)) }
        return parts.joined(separator: " · ")
    }
}

/// Un emplacement : son nom, son etat, sa place, ses jeux, et ce qu'on en fait.
private struct LocationRow: View {
    let location: StorageLocation
    @Binding var removing: StorageLocation?
    @Environment(LibraryModel.self) private var library
    @Environment(\.openWindow) private var openWindow

    private var icon: String {
        if !location.online { return "externaldrive.badge.xmark" }
        return location.isMain ? "internaldrive" : "externaldrive"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(location.online ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: location.name).font(.headline)
                    if location.isDefault {
                        Text("Par défaut")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.green)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                    if !location.online {
                        Text("Débranché")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(verbatim: location.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if let usage = library.usage(of: location) {
                    DiskUsageBar(usage: usage, height: 8)
                        .padding(.vertical, 2)
                }
                Text(verbatim: details)
                    .font(.caption).foregroundStyle(.secondary)
                if let remark = location.explanation {
                    Text(verbatim: remark)
                        .font(.caption)
                        .foregroundStyle(location.online && location.writable != false ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if !location.isDefault {
                    Button("Par défaut") { Task { await library.setDefaultLocation(location) } }
                        .disabled(!location.acceptsGames)
                        .help("Les jeux que Cidre installera iront ici.")
                }
                if !location.isMain {
                    Button("Retirer…") { removing = location }
                        .help("Cidre oublie cet emplacement ; ses jeux restent sur le disque.")
                }
                Button("Jeux…") {
                    library.storagePageLocation = location.id
                    openWindow(id: "stockage")
                }
                .help("Ouvre la page Stockage sur cet emplacement : ses jeux, leur taille, et leur déplacement.")
                if location.online {
                    Button("Afficher") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        let games = location.gamesSummary
        guard location.online, let free = location.freeBytes else { return games }
        // la barre dit deja la place libre
        var parts = library.usage(of: location) == nil ? [L10n.format("%@ libres", L10n.bytes(free)), games] : [games]
        if let fs = location.fileSystem { parts.append(Self.fileSystemName(fs)) }
        return parts.joined(separator: " · ")
    }

    static func fileSystemName(_ fs: String) -> String {
        switch fs {
        case "apfs": "APFS"
        case "exfat": "exFAT"
        case "msdos": "FAT32"
        case "hfs": "Mac OS étendu"
        case "smbfs", "nfs", "afpfs", "webdav": L10n.string("réseau")
        default: fs
        }
    }
}
