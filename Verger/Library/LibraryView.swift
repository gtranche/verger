import CidreBridge
import SwiftUI
import UniformTypeIdentifiers

/// Le verger : la grille des jeux, et la fiche du jeu selectionne.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var selection: Game.ID?
    @State private var choosingCidre = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)]

    var body: some View {
        @Bindable var library = library

        content
            .frame(minWidth: 620, minHeight: 440)
            .navigationTitle("Verger")
            .searchable(text: $library.search, prompt: "Rechercher un jeu")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filtre", selection: $library.filter) {
                        ForEach(LibraryModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Button {
                        Task { await library.reload() }
                    } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                }
            }
            .inspector(isPresented: inspectorShown) {
                if let game = selectedGame {
                    GameDetail(game: game)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
            }
            .alert("Lancement impossible", isPresented: errorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.lastError ?? "")
            }
            .fileImporter(isPresented: $choosingCidre, allowedContentTypes: [.item]) { result in
                if case let .success(url) = result {
                    Task { await library.useCidre(at: url) }
                }
            }
            .task { await library.reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch library.state {
        case .loading:
            ProgressView("Lecture de la bibliothèque…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cidreMissing:
            ContentUnavailableView {
                Label("Cidre introuvable", systemImage: "shippingbox")
            } description: {
                Text("Verger pilote Cidre mais ne le contient pas. Installe Cidre, ou indique où se trouve sa commande `cidre`.")
            } actions: {
                Button("Choisir la commande cidre…") { choosingCidre = true }
                Link("Installer Cidre", destination: URL(string: "https://github.com/gtranche/cidre/releases/latest")!)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Bibliothèque illisible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await library.reload() } }
                Button("Choisir la commande cidre…") { choosingCidre = true }
            }
        case .loaded:
            if library.visibleGames.isEmpty {
                ContentUnavailableView(
                    library.games.isEmpty ? "Aucun jeu installé" : "Aucun jeu ne correspond",
                    systemImage: "leaf")
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(library.visibleGames) { game in
                    // Un bouton, pas un simple geste : la carte reste activable au
                    // clavier et par VoiceOver. Double-clic = jouer.
                    Button {
                        selection = selection == game.id ? nil : game.id
                    } label: {
                        GameCard(
                            game: game,
                            isRunning: library.running.contains(game.appid),
                            isSelected: selection == game.id,
                            play: { library.play(game) }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(game.name)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { library.play(game) })
                }
            }
            .padding(24)
        }
    }

    private var selectedGame: Game? {
        library.games.first { $0.id == selection }
    }

    private var inspectorShown: Binding<Bool> {
        Binding(get: { selectedGame != nil }, set: { if !$0 { selection = nil } })
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
    }
}
