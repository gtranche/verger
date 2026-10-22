import CidreBridge
import SwiftUI

/// La page Stockage, a la maniere de celle de Steam en Big Picture : un disque
/// choisi en haut avec sa barre, tous les jeux qui y sont installes, et leur
/// deplacement vers un autre disque, en file.
struct StorageView: View {
    @Environment(LibraryModel.self) private var library
    @State private var selection: Set<Game.ID> = []
    @State private var sortOrder = [KeyPathComparator(\StorageRow.size, order: .reverse)]

    private var current: StorageLocation? {
        library.locations.first { $0.id == library.storagePageLocation }
            ?? library.locations.first(where: \.isMain) ?? library.locations.first
    }

    var body: some View {
        Group {
            if library.locationsSupported == false {
                ContentUnavailableView {
                    Label("Stockage", systemImage: "externaldrive")
                } description: {
                    Text("Ce Cidre ne sait ranger les jeux que sur ce Mac. Mets-le à jour pour utiliser un disque externe.")
                }
            } else if library.state == .cidreMissing {
                ContentUnavailableView("Cidre n'est pas installé", systemImage: "shippingbox")
            } else if let current {
                page(current)
            } else {
                ProgressView("Lecture des emplacements…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .navigationTitle("Stockage")
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await library.reload()
                        await library.loadLocations()
                    }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            if library.games.isEmpty { await library.reload() }
            await library.loadLocations()
        }
    }

    private func page(_ location: StorageLocation) -> some View {
        let games = library.games(on: location)
        let rows = games.map { StorageRow(game: $0, library: library) }.sorted(using: sortOrder)
        return VStack(spacing: 0) {
            DiskPicker(selected: location.id) { id in
                library.storagePageLocation = id
                selection = []
            }
            Divider()
            DiskHeader(location: location, usage: library.usage(of: location))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            MoveQueueView()
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Jeu", value: \.name, comparator: .localizedStandard) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.game.platform == .macos ? "apple.logo" : "gamecontroller")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(verbatim: row.name)
                    }
                    .opacity(row.game.online ? 1 : 0.5)
                }
                TableColumn("Taille", value: \.size) { row in
                    Text(verbatim: row.size > 0 ? L10n.bytes(row.size) : L10n.string("mesure…"))
                        .monospacedDigit()
                        .foregroundStyle(row.size > 0 ? .primary : .secondary)
                }
                .width(min: 80, ideal: 100, max: 140)
                TableColumn("État") { row in
                    RowStatus(game: row.game)
                }
                .width(min: 160, ideal: 240)
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        location.online ? "Aucun jeu sur ce disque" : "Disque débranché",
                        systemImage: location.online ? "tray" : "externaldrive.badge.xmark")
                }
            }
            Divider()
            // dans l'ordre de la liste : c'est celui de la file
            MoveBar(location: location, selected: rows.map(\.game).filter { selection.contains($0.id) }) {
                selection = []
            }
        }
        .task(id: location.id) { library.measureMissingSizes(games) }
    }
}

/// Une ligne de la liste : le jeu, et ce qui se trie.
struct StorageRow: Identifiable {
    let game: Game
    let name: String
    let size: Int64
    var id: Game.ID { game.id }

    @MainActor
    init(game: Game, library: LibraryModel) {
        self.game = game
        name = game.name
        size = library.size(of: game)
    }
}

/// Les disques de jeux, cote a cote, chacun avec sa barre ; un disque
/// debranche reste grise, sans barre.
private struct DiskPicker: View {
    let selected: String
    let choose: (String) -> Void
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(library.locations) { location in
                    Button { choose(location.id) } label: {
                        DiskTile(location: location, usage: library.usage(of: location), isSelected: location.id == selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

private struct DiskTile: View {
    let location: StorageLocation
    let usage: DiskUsage?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: !location.online ? "externaldrive.badge.xmark" : location.isMain ? "internaldrive" : "externaldrive")
                Text(verbatim: location.name).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
            }
            if let usage {
                DiskUsageBar(usage: usage, height: 6, showsLegend: false)
                Text(verbatim: L10n.format("%@ libres sur %@", L10n.bytes(usage.freeBytes), L10n.bytes(usage.totalBytes)))
                    .font(.caption).foregroundStyle(usage.isNearlyFull ? Color.orange : Color.secondary)
            } else {
                Text(location.online ? "Place inconnue" : "Débranché")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: location.gamesSummary)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 210, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(location.online ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Le disque choisi : son nom, sa grande barre, ce qu'il faut en savoir.
private struct DiskHeader: View {
    let location: StorageLocation
    let usage: DiskUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: location.name).font(.title2.weight(.semibold))
                if location.isDefault {
                    Text("Par défaut")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(.green)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                Spacer()
                if location.online {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
                    }
                    .controlSize(.small)
                }
            }
            if let usage {
                DiskUsageBar(usage: usage, height: 14)
            }
            if let remark = location.explanation {
                Text(verbatim: remark)
                    .font(.caption)
                    .foregroundStyle(location.online && location.writable != false ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(location.online ? 1 : 0.6)
    }
}

/// Ce que devient un jeu : en deplacement, en attente, ou pourquoi il ne se
/// deplace pas d'ici.
private struct RowStatus: View {
    let game: Game
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let status = library.moveStatus(of: game), status.isRunning {
            // compact : l'avancement complet, et l'arret, sont dans la file au-dessus
            HStack(spacing: 6) {
                if status.phase == .copie, let progress = status.progress, progress.totalBytes > 0 {
                    ProgressView(value: progress.fraction).frame(width: 90)
                    Text(verbatim: progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale)))
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.mini)
                    Text(verbatim: status.phaseLabel)
                }
            }
            .foregroundStyle(.secondary)
        } else if let entry = library.moveQueue.pending.first(where: { $0.gameID == game.id }) {
            HStack(spacing: 6) {
                Text(verbatim: L10n.format("En attente → %@", library.location(id: entry.to)?.name ?? entry.to))
                    .foregroundStyle(.secondary)
                Button("Annuler") { library.cancelQueuedMove(game.id) }
                    .controlSize(.small)
            }
        } else {
            Text(verbatim: note).foregroundStyle(.secondary)
        }
    }

    private var note: String {
        if !game.online { return L10n.string("Disque débranché") }
        if library.running.contains(game.id) { return L10n.string("En cours d'exécution") }
        if library.moveStatus(of: game)?.isUnfinished == true { return L10n.string("Déplacement inachevé (voir sa fiche)") }
        switch game.source {
        case .steam: return L10n.string("Installé par Steam : à déplacer depuis Steam")
        case .local: return L10n.string("Hors Steam : ses fichiers restent où ils sont")
        case .battlenet: return L10n.string("Installé par Battle.net : à déplacer depuis son client")
        case .cidre: return ""
        }
    }
}

/// Les deplacements de la file : celui qui tourne, ceux qui attendent.
private struct MoveQueueView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let moving = library.games.filter { library.moveStatus(of: $0)?.isRunning == true }
        let pending = library.moveQueue.pending
        if !moving.isEmpty || !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Déplacements").font(.headline)
                    Spacer()
                    if !pending.isEmpty {
                        Button("Annuler ceux en attente") { library.cancelQueuedMoves() }
                            .controlSize(.small)
                    }
                }
                ForEach(moving) { game in
                    HStack(spacing: 10) {
                        Text(verbatim: L10n.format("%@ → %@", game.name, library.location(id: library.moveStatus(of: game)?.to)?.name ?? "…"))
                            .frame(width: 240, alignment: .leading)
                            .lineLimit(1)
                        if let status = library.moveStatus(of: game) {
                            MoveProgress(status: status) { library.stopMove(game) }
                        }
                    }
                }
                ForEach(pending) { entry in
                    HStack(spacing: 10) {
                        Text(verbatim: L10n.format("%@ → %@", entry.name, library.location(id: entry.to)?.name ?? entry.to))
                            .frame(width: 240, alignment: .leading)
                            .lineLimit(1)
                        Text(verbatim: L10n.format("En attente · %@", L10n.bytes(entry.sizeBytes)))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            library.cancelQueuedMove(entry.gameID)
                        } label: {
                            Label("Annuler", systemImage: "xmark.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Retirer ce jeu de la file : il ne sera pas déplacé.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.4))
        }
    }
}

/// La barre du bas : la selection, et un bouton par disque d'arrivee.
private struct MoveBar: View {
    let location: StorageLocation
    let selected: [Game]
    let didEnqueue: () -> Void
    @Environment(LibraryModel.self) private var library

    private var movable: [Game] { selected.filter(library.canMove) }
    private var movableBytes: Int64 { movable.reduce(0) { $0 + library.size(of: $1) } }
    private var targets: [GameDisk] {
        library.disks.filter { $0.id != location.id && $0.online && $0.acceptsGames }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: selectionText)
                if selected.count > movable.count {
                    Text(verbatim: L10n.format("%@ ne peuvent pas être déplacés d'ici (Steam, hors Steam, en cours…).", String(selected.count - movable.count)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let warning {
                    Text(verbatim: warning).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if targets.isEmpty {
                Text("Aucun autre disque branché : branches-en un pour y déplacer des jeux.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(targets) { target in
                Button {
                    let games = movable
                    Task { await library.enqueueMoves(games, to: target) }
                    didEnqueue()
                } label: {
                    Text(verbatim: L10n.format("Déplacer vers « %@ »", target.name))
                }
                .disabled(movable.isEmpty)
                .help("Copie les jeux un par un sur ce disque, vérifie chaque copie, puis les efface d'ici. Sauvegardes et réglages ne bougent pas.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var selectionText: String {
        switch selected.count {
        case 0: L10n.string("Sélectionne des jeux (⌘ ou ⇧ pour en prendre plusieurs).")
        case 1: L10n.format("1 jeu sélectionné · %@", L10n.bytes(movableBytes))
        default: L10n.format("%@ jeux sélectionnés · %@", String(selected.count), L10n.bytes(movableBytes))
        }
    }

    /// La selection ne tient pas sur un des disques d'arrivee.
    private var warning: String? {
        guard movableBytes > 0 else { return nil }
        let short = targets.filter { target in
            guard let free = target.location.flatMap(library.usage(of:))?.freeBytes ?? target.freeBytes else { return false }
            return free - library.moveQueue.pendingBytes(to: target.id) < movableBytes
        }
        guard !short.isEmpty else { return nil }
        return L10n.format("Pas assez de place sur %@ pour toute la sélection.", short.map { "« \($0.name) »" }.joined(separator: ", "))
    }
}
