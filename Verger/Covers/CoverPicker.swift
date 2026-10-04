import CidreBridge
import SwiftUI

/// « Chercher une jaquette » : SteamGridDB propose des illustrations pour un jeu,
/// qu'il soit sur Steam ou non. On choisit, Verger la telecharge et la pose.
struct CoverPicker: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cleSteamGridDB") private var key = ""

    @State private var term = ""
    @State private var matches: [SteamGridDB.Match] = []
    @State private var selected: SteamGridDB.Match?
    @State private var grids: [SteamGridDB.Grid] = []
    @State private var busy = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Jaquette de \(game.name)").font(.headline).lineLimit(1)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()

            if key.trimmingCharacters(in: .whitespaces).isEmpty {
                keyRequest
            } else {
                search
            }
        }
        .frame(width: 560, height: 560)
        .task {
            term = game.name
            if !key.isEmpty { await find() }
        }
    }

    /// Sans cle, on explique d'ou elle vient et on la demande.
    private var keyRequest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Les jaquettes viennent de SteamGridDB, une base d'illustrations tenue par des joueurs. Son accès demande une clé personnelle, gratuite : crée un compte sur leur site, copie ta clé d'API et colle-la ici.")
                .fixedSize(horizontal: false, vertical: true)
            Link("Ouvrir la page de la clé sur steamgriddb.com", destination: SteamGridDB.keyPage)
            SecureField("Clé d'API SteamGridDB", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await find() } }
            Text("La clé est gardée dans les préférences de Verger, sur ce Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var search: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Nom du jeu", text: $term)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await find() } }
                Button("Chercher") { Task { await find() } }.disabled(busy || term.isEmpty)
            }
            .padding(.horizontal)

            if matches.count > 1 {
                Picker("Jeu", selection: $selected) {
                    ForEach(matches) { Text($0.name).tag(Optional($0)) }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: selected) { _, match in
                    if let match { Task { await load(match) } }
                }
            }
            Divider().padding(.top, 10)

            if let error {
                ContentUnavailableView {
                    Label("Recherche impossible", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Changer de clé") { key = "" }
                }
            } else if busy {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if grids.isEmpty {
                ContentUnavailableView("Aucune jaquette trouvée", systemImage: "photo",
                                       description: Text("Essaie un autre nom, ou choisis une image sur ton Mac."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(grids) { grid in
                            Button {
                                Task { await choose(grid) }
                            } label: {
                                AsyncImage(url: grid.thumb) { image in
                                    image.resizable()
                                } placeholder: {
                                    Rectangle().fill(.quaternary)
                                }
                                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Choisir cette jaquette")
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func find() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let api = SteamGridDB(key: key)
            // Un jeu Steam se retrouve par son appid ; sinon, par son nom.
            if let appid = game.appid, term == game.name {
                let direct = try await api.grids(forSteamApp: appid)
                if !direct.isEmpty {
                    matches = []
                    grids = direct
                    return
                }
            }
            matches = try await api.search(term)
            selected = matches.first
            if let first = matches.first {
                grids = try await api.grids(forGame: first.id)
            } else {
                grids = []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func load(_ match: SteamGridDB.Match) async {
        busy = true
        defer { busy = false }
        do {
            grids = try await SteamGridDB(key: key).grids(forGame: match.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func choose(_ grid: SteamGridDB.Grid) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: grid.url)
            try CoverStore.shared.setCover(for: game.id, data: data, fileExtension: grid.url.pathExtension)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
