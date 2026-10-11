import CidreBridge
import SwiftUI

/// « Partager mon résultat » : un verdict, des fps, des notes, et l'apercu du
/// rapport. Verger prepare un incident GitHub au format des fiches de Cidre ;
/// c'est l'utilisateur qui l'envoie, depuis la page de GitHub.
struct GameReportSheet: View {
    let game: Game
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var verdict: GameReport.Verdict = .silver
    @State private var fpsMenu: Int?
    @State private var fpsGame: Int?
    @State private var notes = ""
    /// Ce que Verger a lu de la machine et de l'installation ; `nil` tant que
    /// le diagnostic tourne.
    @State private var context: GameReport.Context?
    @State private var copied = false
    @State private var attachment: URL?

    private var report: GameReport {
        GameReport(context: context ?? GameReport.Context(), verdict: verdict, fpsMenu: fpsMenu, fpsGame: fpsGame, notes: notes)
    }

    private var issue: IssueReport {
        report.issue(gameName: game.name, gameID: game.appid.map(String.init) ?? game.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Partager mon résultat", systemImage: "hand.thumbsup")
                .font(.headline)
            Text("Dis comment \(game.name) tourne sur ton Mac : ton rapport nourrit la fiche du jeu, et aide les autres joueurs. GitHub s'ouvre avec ce texte, tu le relis et tu le publies. Il faut un compte GitHub.")
                .fixedSize(horizontal: false, vertical: true)

            Picker("Verdict", selection: $verdict) {
                ForEach(GameReport.Verdict.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)

            HStack(spacing: 16) {
                fpsField("Images par seconde au menu", value: $fpsMenu)
                fpsField("Images par seconde en jeu", value: $fpsGame)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.callout)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                Text("Ce qui marche, ce qui coince, les options qui ont aidé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Aperçu du rapport").font(.callout)
                    Spacer()
                    if context == nil {
                        ProgressView().controlSize(.small)
                        Text("Diagnostic en cours… Il peut durer une minute.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    Text(verbatim: issue.body())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            Label("L'incident sera public. Ton nom de session, tes identifiants Steam et le nom de ton Mac ont été retirés : relis quand même avant d'envoyer.", systemImage: "eye")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let attachment {
                HStack {
                    Text("Une adresse web ne porte que le début du diagnostic. Pour le joindre en entier, glisse ce fichier dans l'incident :")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Afficher le fichier") {
                        NSWorkspace.shared.activateFileViewerSelecting([attachment])
                    }
                }
            }

            HStack {
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? "Copié" : "Copier le rapport") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(issue.body(), forType: .string)
                    copied = true
                }
                .disabled(context == nil)
                Button("Ouvrir sur GitHub") {
                    let issue = issue
                    let url = issue.url()
                    // le diagnostic coupe dans l'adresse : le rapport entier en fichier
                    if url.absoluteString.utf8.count < issue.url(maxLength: .max).absoluteString.utf8.count {
                        attachment = library.saveGameReport(issue, gameID: game.id)
                    }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(context == nil)
            }
        }
        .padding(20)
        .frame(width: 640, height: 700)
        .task {
            context = await library.gameReportContext(for: game)
        }
    }

    private func fpsField(_ title: LocalizedStringKey, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField("Facultatif", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
        }
    }
}
