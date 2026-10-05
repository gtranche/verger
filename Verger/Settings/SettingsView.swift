import CidreBridge
import SwiftUI

/// Les réglages (⌘,) : l'etat de Cidre, le compte Steam, les options generales
/// de lancement, et Verger lui-meme.
struct SettingsView: View {
    /// Le dernier onglet ouvert, retrouve a la prochaine ouverture.
    @AppStorage("ongletReglages") private var tab = "cidre"

    var body: some View {
        TabView(selection: $tab) {
            CidreSettings().tabItem { Label("Cidre", systemImage: "shippingbox") }.tag("cidre")
            SteamSettings().tabItem { Label("Steam", systemImage: "person.crop.circle") }.tag("steam")
            OptionsSettings().tabItem { Label("Options", systemImage: "slider.horizontal.3") }.tag("options")
            VergerSettings().tabItem { Label("Verger", systemImage: "leaf") }.tag("verger")
        }
        .frame(width: 520, height: 520)
    }
}

// MARK: Cidre

private struct CidreSettings: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Form {
            if let status = library.runtimeStatus {
                Section("Version") {
                    LabeledContent("Installée", value: status.isDevelopmentCheckout ? L10n.string("Dépôt de développement") : status.version)
                    if let update = library.availableUpdate {
                        LabeledContent("Disponible") {
                            Text(update.version).foregroundStyle(.orange)
                        }
                    } else if !status.isDevelopmentCheckout {
                        LabeledContent("Disponible", value: L10n.string("À jour"))
                    }
                    LabeledContent("Emplacement") {
                        Text(status.root).font(.callout).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    }
                }
                Section("État") {
                    check("Runtime (Wine, DXVK, pilote Vulkan)", status.runtimePresent)
                    check("Préfixe Wine", status.prefixReady)
                    check("SteamCMD", status.steamcmdPresent)
                    check("Bibliothèques (SPIRV-Tools, FreeType)",
                          status.prerequisites.missing.isEmpty,
                          problem: L10n.format("Manque : %@", status.prerequisites.missing.joined(separator: ", ")))
                    LabeledContent("Jeu en cours", value: L10n.string(status.gameRunning ? "Oui" : "Non"))
                }
                Section {
                    if let step = library.runtimeStep {
                        RuntimeProgress(step: step) { library.cancelRuntimeInstall() }
                    } else {
                        HStack {
                            Button("Rechercher une mise à jour") { Task { await library.checkRuntime() } }
                            if library.availableUpdate != nil {
                                Button("Mettre à jour") { library.installRuntime() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(status.gameRunning)
                            }
                            Spacer()
                            Button("Reconfigurer") { library.reconfigureRuntime() }
                                .disabled(status.gameRunning)
                                .help("Relance la configuration de Cidre (préfixe Wine, pont Steam, SteamCMD). Tes jeux et sauvegardes ne sont pas touchés.")
                        }
                    }
                } footer: {
                    if status.isDevelopmentCheckout {
                        Text("Un dépôt de développement n'est jamais mis à jour par Verger.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if library.cli == nil {
                Section {
                    Text("Cidre n'est pas installé. La fenêtre principale propose de l'installer.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Ce Cidre est trop ancien pour décrire son état. Mets-le à jour.")
                        .foregroundStyle(.secondary)
                    Button("Rechercher une mise à jour") { Task { await library.checkRuntime() } }
                }
            }
        }
        .formStyle(.grouped)
        .task { await library.checkRuntime() }
    }

    private func check(_ title: LocalizedStringKey, _ ok: Bool, problem: String = L10n.string("Absent")) -> some View {
        LabeledContent(title) {
            Label(ok ? L10n.string("Prêt") : problem, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }
}

// MARK: Steam

private struct SteamSettings: View {
    @Environment(LibraryModel.self) private var library
    @State private var loggingIn = false
    @State private var confirmingLogout = false

    var body: some View {
        Form {
            Section("Compte") {
                if let session = library.steamSession {
                    LabeledContent("Identifiant", value: session.account.isEmpty ? L10n.string("Aucun") : session.account)
                    LabeledContent("Session") {
                        Label(L10n.string(session.connected ? "Connecté" : "Déconnecté"),
                              systemImage: session.connected ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(session.connected ? .green : .secondary)
                    }
                    HStack {
                        if session.connected {
                            Button("Se déconnecter…") { confirmingLogout = true }
                            Button("Changer de compte…") { loggingIn = true }
                        } else {
                            Button("Se connecter…") { loggingIn = true }
                                .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                        Button("Revérifier") { Task { await library.checkSession() } }
                            .disabled(library.checkingSession)
                    }
                } else if library.checkingSession {
                    HStack { ProgressView().controlSize(.small); Text("Vérification de la session…") }
                } else {
                    Text("Ce Cidre ne sait pas dire l'état de la session. Mets-le à jour.")
                        .foregroundStyle(.secondary)
                    Button("Se connecter…") { loggingIn = true }
                }
            }
            Section("Sans connexion") {
                Text("Tes jeux installés restent jouables : jouer ne demande pas cette session. Elle sert à lire la liste de tes jeux, à en installer et à les mettre à jour.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Les jeux Steam ont en revanche besoin du client Steam ouvert pendant la partie (succès, amis, vérification de la licence) ; hors ligne, c'est son mode hors ligne qui s'applique.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await library.checkSession() }
        .sheet(isPresented: $loggingIn, onDismiss: { Task { await library.checkSession() } }) {
            LoginSheet().environment(library)
        }
        .confirmationDialog("Se déconnecter de Steam ?", isPresented: $confirmingLogout) {
            Button("Se déconnecter", role: .destructive) { Task { await library.logout() } }
        } message: {
            Text("Verger oublie la session. Tes jeux installés restent en place et jouables ; il faudra te reconnecter pour en installer ou les mettre à jour.")
        }
    }
}

// MARK: Options generales

private struct OptionsSettings: View {
    @Environment(LibraryModel.self) private var library
    @State private var defaults: DefaultOptions?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                if let defaults {
                    LaunchOptionsEditor(
                        targetID: CidreCLI.defaultsID, scope: .general,
                        options: defaults.options, overridden: defaults.overridden
                    ) { change in
                        Task {
                            if let updated = await library.changeDefaultOptions(change) { self.defaults = updated }
                        }
                    }
                } else if loaded {
                    Text("Ce Cidre ne connaît pas les réglages généraux. Mets-le à jour.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            } header: {
                Text("Pour tous les jeux lancés par Cidre")
            } footer: {
                Text("Chaque jeu suit ces réglages, sauf ceux que Cidre livre pour lui et ceux que tu forces dans sa fiche.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            defaults = await library.defaultOptions()
            loaded = true
        }
    }
}

// MARK: Verger

private struct VergerSettings: View {
    @Environment(AppUpdateModel.self) private var updater
    @Environment(LibraryModel.self) private var library
    @AppStorage("langue") private var language = ""
    @AppStorage("cleSteamGridDB") private var gridKey = ""

    var body: some View {
        @Bindable var library = library

        Form {
            Section {
                Picker("Langue de Verger", selection: $language) {
                    Text("Celle de macOS").tag("")
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "English").tag("en")
                }
            } footer: {
                Text("Les menus de macOS en haut de l'écran changent à la prochaine ouverture de Verger.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Version") {
                LabeledContent("Installée", value: updater.currentVersion ?? L10n.string("Lancé hors application"))
                if let update = updater.available {
                    LabeledContent("Disponible") { Text(update.version).foregroundStyle(.orange) }
                } else if updater.latest != nil {
                    LabeledContent("Disponible", value: L10n.string("À jour"))
                }
                if let date = updater.lastCheck {
                    LabeledContent("Dernière vérification") { Text(date, style: .time) }
                }
            }
            Section {
                switch updater.state {
                case let .downloading(done, total):
                    ProgressView(value: total > 0 ? min(Double(done) / Double(total), 1) : 0)
                    Text("Téléchargement de Verger…").font(.callout)
                case .checking:
                    HStack { ProgressView().controlSize(.small); Text("Vérification…") }
                case .idle, .failed:
                    HStack {
                        Button("Rechercher une mise à jour") { Task { await updater.check() } }
                        if updater.available != nil {
                            Button("Mettre à jour et relancer") { Task { await updater.install() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if case let .failed(message) = updater.state {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                }
            } footer: {
                Text("Verger se met à jour depuis ses versions publiées sur GitHub, séparément de Cidre : une mise à jour de l'interface ne retélécharge pas le moteur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Afficher le jeu en cours sur Discord", isOn: $library.discordEnabled)
            } header: {
                Text(verbatim: "Discord")
            } footer: {
                Text("Tes amis voient le jeu auquel tu joues, avec son nom et son icône, comme si Discord l'avait reconnu lui-même. Il faut que Discord connaisse le jeu, et que Verger et Discord restent ouverts pendant la partie.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                SecureField("Clé d'API SteamGridDB", text: $gridKey)
                Link("Ouvrir la page de la clé sur steamgriddb.com", destination: SteamGridDB.keyPage)
            } header: {
                Text("Jaquettes")
            } footer: {
                Text("Pour chercher des jaquettes (jeux non-Steam, ou une image que tu préfères) depuis la fiche d'un jeu. La clé est gratuite et reste dans les préférences de Verger, sur ce Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { if updater.latest == nil { await updater.check() } }
    }
}
