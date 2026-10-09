import CidreBridge
import SwiftUI

/// L'avancement d'une installation ou d'une mise a jour de Cidre.
struct RuntimeProgress: View {
    let step: RuntimeInstaller.Step
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                switch step {
                case let .downloading(done, total) where total > 0:
                    ProgressView(value: min(Double(done) / Double(total), 1))
                    Text("Téléchargement de Cidre — \(L10n.bytes(done)) sur \(L10n.bytes(total))")
                case .downloading:
                    ProgressView().progressViewStyle(.linear)
                    Text("Téléchargement de Cidre…")
                case .extracting:
                    ProgressView().progressViewStyle(.linear)
                    Text("Décompression…")
                case let .configuring(what):
                    ProgressView().progressViewStyle(.linear)
                    Text("Configuration — \(what)")
                }
            }
            .font(.callout)
            Button("Annuler", action: cancel)
        }
    }
}

/// Cidre n'est pas installe : Verger l'installe lui-meme.
struct RuntimeMissingView: View {
    @Environment(LibraryModel.self) private var library
    let chooseCidre: () -> Void

    var body: some View {
        if let step = library.runtimeStep {
            VStack(spacing: 16) {
                Image(systemName: "shippingbox").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Installation de Cidre").font(.title2.weight(.semibold))
                RuntimeProgress(step: step) { library.cancelRuntimeInstall() }
                    .frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Cidre n'est pas installé", systemImage: "shippingbox")
            } description: {
                Text("Cidre est le moteur qui fait tourner les jeux Windows. Verger le télécharge (environ 400 Mo) et le configure pour toi.")
            } actions: {
                Button("Installer Cidre") { library.installRuntime() }
                    .buttonStyle(.borderedProminent)
                Button("J'ai déjà Cidre ailleurs…", action: chooseCidre)
            }
        }
    }
}

/// Les bandeaux au-dessus de la grille : mise a jour de Cidre, prerequis manquants.
struct RuntimeBanners: View {
    @Environment(LibraryModel.self) private var library
    @Environment(AppUpdateModel.self) private var updater

    /// La version de Verger en cours, pour les bandeaux.
    private var currentVersion: String { updater.currentVersion ?? "?" }

    var body: some View {
        VStack(spacing: 0) {
            if let update = updater.available {
                banner {
                    if case let .downloading(done, total) = updater.state {
                        ProgressView(value: total > 0 ? min(Double(done) / Double(total), 1) : 0)
                        Text("Téléchargement de Verger \(update.version)…")
                    } else {
                        Label("Verger \(update.version) est disponible (tu as la \(currentVersion)).", systemImage: "leaf")
                        Spacer()
                        Button("Mettre à jour et relancer") { Task { await updater.install() } }
                            .disabled(!library.running.isEmpty)
                            .help(library.running.isEmpty ? "Verger se remplace et se relance." : "Attends la fin du jeu en cours.")
                    }
                }
            }
            if let step = library.runtimeStep {
                banner {
                    RuntimeProgress(step: step) { library.cancelRuntimeInstall() }
                }
            } else if let update = library.availableUpdate, let status = library.runtimeStatus {
                banner {
                    Label("Cidre \(update.version) est disponible (tu as la \(status.version)).", systemImage: "arrow.down.circle")
                    Spacer()
                    Button("Mettre à jour") { library.installRuntime() }
                        .disabled(status.gameRunning || !library.running.isEmpty)
                        .help(status.gameRunning ? "Quitte d'abord le jeu en cours." : "Tes jeux, sauvegardes et réglages sont conservés.")
                }
            }
            if library.runtimeStep == nil, let status = library.runtimeStatus {
                if status.steamClientInstalled == false {
                    banner {
                        Label("Le client Steam n'est pas installé. Il en faut un, connecté à ton compte, pour installer et lancer tes jeux Steam.", systemImage: "exclamationmark.triangle")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Link("Télécharger Steam", destination: URL(string: "https://store.steampowered.com/about/")!)
                        Button("Revérifier") { Task { await library.checkRuntime() } }
                    }
                }
                if !status.steamcmdPresent {
                    banner {
                        Label("SteamCMD, l'outil de Valve qui télécharge les jeux, n'a pas pu être installé. Vérifie ta connexion à Internet.", systemImage: "exclamationmark.triangle")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Réessayer") { library.reconfigureRuntime() }
                    }
                }
            }
            if let missing = library.runtimeStatus?.prerequisites.missing, !missing.isEmpty {
                let command = "brew install " + missing.joined(separator: " ")
                let missingList = missing.joined(separator: ", ")
                banner {
                    Label("Il manque \(missingList) : sans eux, les jeux Windows ne s'affichent pas.", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Text(command).font(.callout.monospaced()).textSelection(.enabled)
                    Button("Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    Button("Revérifier") { Task { await library.checkRuntime() } }
                }
            }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { content() }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }
}
