import Foundation
import Testing

@testable import CidreBridge

/// La mise a jour d'un jeu avant son lancement (Cidre 1.5.10) : l'etat que
/// rendent `cidre updates --json` et `cidre info --json`, les evenements de
/// `cidre play --json`, et ce que fait le bouton « Jouer ». Un Cidre plus ancien
/// n'ecrit rien de tout cela : le decodage doit rester valide.
struct UpdateBeforeLaunchTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func game(source: String, installed: Bool = true, platform: String = "windows") throws -> Game {
        try decode(Game.self, """
        {"id":"9001","appid":9001,"nom":"Jeu","plateforme":"\(platform)","lancement":"\(platform == "macos" ? "natif" : "cidre")","source":"\(source)","installe":\(installed),"wrapper":null,"chemin":"/x","taille":1,"dernier_lancement":0}
        """)
    }

    // MARK: cidre updates --json

    @Test func updateFromOlderCidre() throws {
        let u = try decode(GameUpdate.self, """
        {"appid": 588650, "build_installe": 1, "build_disponible": 23762174, "a_jour": false}
        """)
        #expect(u.status == nil && u.source == nil)
        #expect(u.needsUpdate)
    }

    /// Cidre <= 1.5.9 comparait par egalite : apres un `cidre dl`, son cache
    /// d'une demi-heure donnait un build « publie » plus ancien que l'installe,
    /// et le jeu restait « pas a jour ». Ce n'est pas une mise a jour.
    @Test func installedAheadOfStaleCacheIsNotAnUpdate() throws {
        let u = try decode(GameUpdate.self, """
        {"appid": 1903340, "build_installe": 23765773, "build_disponible": 23000000, "a_jour": false}
        """)
        #expect(!u.needsUpdate)
        #expect(try PlayPlan.plan(for: game(source: "cidre"), update: u) == .play)
    }

    @Test func updateStates() throws {
        let list = try decode([GameUpdate].self, """
        [{"appid": 1, "build_installe": 5, "build_disponible": 5, "a_jour": true, "source": "steam", "etat": "a_jour"},
         {"appid": 2, "build_installe": 5, "build_disponible": 7, "a_jour": false, "source": "cidre", "etat":"disponible","raison":null,"message":null,"avancement":null,"octets":null,"total":null,"phase":null,"avant_lancement":true,"verifie":1791922051},
         {"appid": 3, "build_installe": 5, "build_disponible": 7, "a_jour": false, "source": "cidre", "etat":"en_cours","raison":null,"message":null,"avancement":37.93,"octets":32564012,"total":85850313,"phase":"downloading","avant_lancement":true,"verifie":1791922051},
         {"appid": 4, "build_installe": 5, "build_disponible": 7, "a_jour": false, "source": "cidre", "etat":"echouee","raison":"disque","message":"Mise a jour impossible : place insuffisante sur le disque des jeux (200 Mo libres, il en faut au moins 1024). Libere de la place, puis relance le jeu.","avancement":null,"octets":null,"total":null,"phase":null,"avant_lancement":true,"verifie":1791922051},
         {"appid": 5, "build_installe": 5, "build_disponible": 7, "a_jour": false, "source": "cidre", "etat":"ignoree","raison":"option","message":null,"avancement":null,"octets":null,"total":null,"phase":null,"avant_lancement":false,"verifie":1791922051},
         {"appid": 6, "build_installe": 5, "build_disponible": 7, "a_jour": false, "source": "cidre", "etat":"etat_de_demain","raison":"raison_de_demain","avant_lancement":true}]
        """)
        #expect(list.map(\.needsUpdate) == [false, true, true, true, true, true])
        #expect(list[0].source == "steam" && list[0].status?.state == .upToDate)
        #expect(list[1].status?.state == .available && list[1].status?.beforeLaunch == true)
        #expect(list[1].status?.progress == nil && list[1].status?.reason == nil)
        #expect(list[2].status?.state == .running)
        let downloading = try #require(list[2].status?.progress)
        #expect(abs(downloading.fraction - 0.3793) < 1e-9)
        #expect(downloading.doneBytes == 32_564_012 && downloading.totalBytes == 85_850_313)
        #expect(list[3].status?.state == .failed && list[3].status?.reason == .disk)
        #expect(list[3].status?.message?.hasPrefix("Mise a jour impossible") == true)
        #expect(list[3].status?.explanation != nil)
        #expect(list[4].status?.state == .ignored && list[4].status?.reason == .option)
        #expect(list[4].status?.beforeLaunch == false)
        // un etat ou une raison que ce Verger ne connait pas ne font pas tomber la liste
        #expect(list[5].status?.state == .unknown && list[5].status?.reason == .other)
    }

    /// Chaque echec et chaque verification impossible ont leur phrase : la
    /// cause probable, et quoi faire.
    @Test func everyFailureIsExplained() throws {
        for reason in ["session", "disque", "reseau", "licence", "compte", "interrompue", "steamcmd", "raison_de_demain"] {
            let s = try decode(UpdateStatus.self, #"{"etat":"echouee","raison":"\#(reason)","message":"detail de Cidre"}"#)
            #expect(s.explanation?.isEmpty == false, "echouee/\(reason)")
        }
        for reason in ["hors_ligne", "trop_lent", "steamcmd_absent"] {
            let s = try decode(UpdateStatus.self, #"{"etat":"inconnu","raison":"\#(reason)"}"#)
            #expect(s.explanation?.isEmpty == false, "inconnu/\(reason)")
        }
        for reason in ["option", "branche", "sans_effet"] {
            let s = try decode(UpdateStatus.self, #"{"etat":"ignoree","raison":"\#(reason)"}"#)
            #expect(s.explanation?.isEmpty == false, "ignoree/\(reason)")
        }
        // rien a dire : a jour, jamais verifie, laissee de cote a la demande
        #expect(try decode(UpdateStatus.self, #"{"etat":"a_jour"}"#).explanation == nil)
        #expect(try decode(UpdateStatus.self, #"{"etat":"inconnu","raison":"jamais_verifie"}"#).explanation == nil)
        #expect(try decode(UpdateStatus.self, #"{"etat":"ignoree","raison":"demande"}"#).explanation == nil)
        // l'echec que Verger ne sait pas nommer garde le detail de Cidre
        let other = try decode(UpdateStatus.self, #"{"etat":"echouee","raison":"steamcmd","message":"Error! App '1' state is 0x6"}"#)
        #expect(other.explanation?.contains("0x6") == true)
    }

    // MARK: cidre info --json

    @Test func infoCarriesUpdateStatus() throws {
        let info = try decode(GameInfo.self, """
        {"id":"9003","appid":9003,"nom":"Jeu 9003","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/x","taille":1000,"dernier_lancement":0,"sauvegardes":false,"options":{"tso":true,"maj_avant_lancement":false},"options_perso":{"maj_avant_lancement":false},"maj":{"etat":"echouee","build_installe":100,"build_disponible":200,"raison":"session","message":"Mise a jour impossible : la session Steam n'est pas memorisee.","avancement":null,"octets":null,"total":null,"phase":null,"avant_lancement":false,"verifie":1791922051},"fiche":null}
        """)
        #expect(info.game.installed)
        #expect(info.update?.state == .failed && info.update?.reason == .session)
        #expect(info.update?.installedBuild == 100 && info.update?.availableBuild == 200)
        #expect(info.options.updateBeforeLaunch == false)
        #expect(info.overridden == [.updateBeforeLaunch])
        #expect(info.options.summary.contains("maj_avant_lancement=false"))
        #expect(LaunchOptions.Key.updateBeforeLaunch.rawValue == "maj_avant_lancement")
    }

    @Test func infoWithoutUpdateStatus() throws {
        // un jeu du client Steam ("maj": null), puis un Cidre qui ne connait pas le champ
        for maj in [#","maj":null"#, ""] {
            let info = try decode(GameInfo.self, """
            {"id":"1","appid":1,"nom":"X","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"wrapper":false,"chemin":"/x","taille":0,"dernier_lancement":0,"options":{"tso":true}\(maj)}
            """)
            #expect(info.update == nil)
            #expect(info.options.updateBeforeLaunch == nil)
        }
    }

    // MARK: cidre play --json

    @Test func playEvents() {
        #expect(PlayEvent.parse(line: #"{"evenement":"lancement"}"#) == .launching)
        guard case let .update(checking)? = PlayEvent.parse(line: #"{"evenement":"maj","etat":"verification"}"#) else {
            Issue.record("verification non lue"); return
        }
        #expect(checking.state == .checking && checking.progress == nil)
        guard case let .update(progress)? = PlayEvent.parse(
            line: #"{"evenement":"maj","etat":"en_cours","avancement":37.93,"octets":32564012,"total":85850313,"phase":"downloading"}"# + "\r\n") else {
            Issue.record("avancement non lu"); return
        }
        #expect(progress.state == .running)
        #expect(abs((progress.progress?.fraction ?? 0) - 0.3793) < 1e-9)
        #expect(progress.progress?.doneBytes == 32_564_012 && progress.progress?.totalBytes == 85_850_313)
        guard case let .update(started)? = PlayEvent.parse(
            line: #"{"evenement":"maj","etat":"en_cours","build_installe":100,"build_disponible":200,"raison":null,"message":null,"avancement":null,"octets":null,"total":null,"phase":null,"avant_lancement":true,"verifie":1791922051}"#) else {
            Issue.record("annonce non lue"); return
        }
        #expect(started.state == .running && started.progress == nil && started.availableBuild == 200)
        guard case let .update(failed)? = PlayEvent.parse(
            line: #"{"evenement":"maj","etat":"echouee","build_installe":200,"build_disponible":300,"raison":"session","message":"Mise a jour impossible : la session Steam n'est pas memorisee.","avancement":null,"octets":null,"total":null,"phase":null,"avant_lancement":true,"verifie":null}"#) else {
            Issue.record("echec non lu"); return
        }
        #expect(failed.state == .failed && failed.reason == .session)
        guard case let .update(done)? = PlayEvent.parse(line: #"{"evenement":"maj","etat":"faite","build_installe":200}"#) else {
            Issue.record("fin non lue"); return
        }
        #expect(done.state == .done && done.installedBuild == 200)
        // ce qui n'est pas un evenement : la sortie d'un lanceur, un evenement de demain, du JSON casse
        #expect(PlayEvent.parse(line: "lancement Cidre : Jeu.exe  (appid 9001)") == nil)
        #expect(PlayEvent.parse(line: "") == nil)
        #expect(PlayEvent.parse(line: #"{"evenement":"de_demain"}"#) == nil)
        #expect(PlayEvent.parse(line: #"{"evenement":"maj","etat":"#) == nil)
        #expect(PlayEvent.parse(line: #"{"autre":1}"#) == nil)
    }

    // MARK: le bouton Jouer

    @Test func playButton() throws {
        let available = try decode(GameUpdate.self, #"{"appid":9001,"build_installe":5,"build_disponible":7,"a_jour":false,"source":"cidre","etat":"disponible","avant_lancement":true}"#)
        let failed = try decode(GameUpdate.self, #"{"appid":9001,"build_installe":5,"build_disponible":7,"a_jour":false,"source":"cidre","etat":"echouee","raison":"reseau","avant_lancement":true}"#)
        let optionOff = try decode(GameUpdate.self, #"{"appid":9001,"build_installe":5,"build_disponible":7,"a_jour":false,"source":"cidre","etat":"ignoree","raison":"option","avant_lancement":false}"#)
        let branch = try decode(GameUpdate.self, #"{"appid":9001,"build_installe":5,"build_disponible":7,"a_jour":false,"source":"cidre","etat":"ignoree","raison":"branche","avant_lancement":true}"#)
        let upToDate = try decode(GameUpdate.self, #"{"appid":9001,"build_installe":7,"build_disponible":7,"a_jour":true,"source":"cidre","etat":"a_jour","avant_lancement":true}"#)
        let old = try decode(GameUpdate.self, #"{"appid":9001,"build_installe":5,"build_disponible":7,"a_jour":false}"#)
        let cidre = try game(source: "cidre")

        // un build plus recent : « Jouer » met a jour d'abord -- y compris apres un echec, et avec un Cidre plus ancien
        #expect(PlayPlan.plan(for: cidre, update: available) == .updateThenPlay)
        #expect(PlayPlan.plan(for: cidre, update: failed) == .updateThenPlay)
        #expect(PlayPlan.plan(for: cidre, update: old) == .updateThenPlay)
        // rien a faire, ou rien de voulu : on lance
        #expect(PlayPlan.plan(for: cidre, update: nil) == .play)
        #expect(PlayPlan.plan(for: cidre, update: upToDate) == .play)
        #expect(PlayPlan.plan(for: cidre, update: optionOff) == .play)
        #expect(PlayPlan.plan(for: cidre, update: branch) == .play)
        // un telechargement inacheve se reprend, il ne se « met pas a jour »
        #expect(try PlayPlan.plan(for: game(source: "cidre", installed: false), update: available) == .play)
        // un jeu du client Steam (natif, ou Windows par le wrapper) : Steam le met a jour ; hors Steam : pas de build
        #expect(try PlayPlan.plan(for: game(source: "steam", platform: "macos"), update: old) == .play)
        #expect(try PlayPlan.plan(for: game(source: "steam"), update: available) == .play)
        #expect(try PlayPlan.plan(for: game(source: "local"), update: available) == .play)
    }

    // MARK: bout en bout, sur une fausse CLI

    @Test func playWithEvents() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("cidre")
        try #"""
            #!/bin/sh
            echo "$*" >>"$(dirname "$0")/appels.txt"
            [ "$1" = play ] || exit 2
            case "$2" in
              1) echo '{"evenement":"maj","etat":"verification"}'
                 echo '{"evenement":"maj","etat":"en_cours","build_installe":100,"build_disponible":200,"avancement":null}'
                 echo "Mise a jour avant le lancement : build 100 -> 200" >&2
                 printf '{"evenement":"maj","etat":"en_cours","avancement":50.00,"octets":5,"total":10,"phase":"downloading"}\n{"evenement":"maj",'
                 sleep 0.2
                 printf '"etat":"faite","build_installe":200}\n{"evenement":"lancement"}\n'
                 exec >&2
                 echo "lancement Cidre : Jeu.exe  (appid 1)" ;;
              2) echo '{"evenement":"maj","etat":"verification"}'
                 echo '{"evenement":"maj","etat":"echouee","build_installe":100,"build_disponible":200,"raison":"session","message":"Mise a jour impossible"}'
                 echo '{"evenement":"lancement"}'
                 echo "une ligne qui n'est pas un evenement" ;;
              3) echo '{"evenement":"maj","etat":"en_cours","avancement":12.50,"octets":125,"total":1000}'
                 sleep 30 ;;
              4) echo "Une mise a jour de ce jeu est deja en cours (processus 42)" >&2; exit 4 ;;
              5) echo '{"evenement":"lancement"}'; echo "    cause probable : x" >&2; exit 1 ;;
            esac
            """#.write(to: script, atomically: true, encoding: .utf8)
        let cli = CidreCLI(executable: script)
        let log = dir.appendingPathComponent("logs/play.log")

        // mise a jour puis lancement : les evenements dans l'ordre, le reste au journal
        let seen = Events()
        try await cli.play(id: "1", log: log) { seen.add($0) }
        #expect(seen.all.count == 5)
        #expect(seen.states == [.checking, .running, .running, .done])
        #expect(seen.all.last == .launching)
        if case let .update(status) = seen.all[2] {
            #expect(status.progress == DownloadProgress(fraction: 0.5, doneBytes: 5, totalBytes: 10))
        } else { Issue.record("avancement attendu en troisieme") }
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "Mise a jour avant le lancement : build 100 -> 200\nlancement Cidre : Jeu.exe  (appid 1)\n")

        // echec : raconte, puis le jeu part quand meme ; une ligne ordinaire rejoint le journal
        let failed = Events()
        try await cli.play(id: "2", log: log, skipUpdate: false) { failed.add($0) }
        #expect(failed.states == [.checking, .failed] && failed.all.last == .launching)
        #expect(try String(contentsOf: log, encoding: .utf8) == "une ligne qui n'est pas un evenement\n")

        // jouer sans mettre a jour : --sans-maj, apres l'identifiant
        try await cli.play(id: "2", log: log, skipUpdate: true) { _ in }
        #expect(try String(contentsOf: dir.appendingPathComponent("appels.txt"), encoding: .utf8)
            == "play 1 --json\nplay 2 --json\nplay 2 --json --sans-maj\n")

        // une mise a jour tourne deja ailleurs (code 4) : une erreur qui le dit
        await #expect(throws: CidreError.updateRunning) { try await cli.play(id: "4", log: log) { _ in } }
        #expect(CidreError.updateRunning.errorDescription?.isEmpty == false)
        // le jeu sort en erreur : comme avant, avec le journal pour l'expliquer
        do {
            try await cli.play(id: "5", log: log) { _ in }
            Issue.record("un play en echec doit lever")
        } catch let CidreError.commandFailed(command, status, _) {
            #expect(command == "play 5" && status == 1)
            #expect(try String(contentsOf: log, encoding: .utf8).contains("cause probable : x"))
        }

        // a l'ouverture de Verger : rafraichir en fond, sans rien attendre ni lever
        await cli.refreshUpdatesInBackground()
        #expect(try String(contentsOf: dir.appendingPathComponent("appels.txt"), encoding: .utf8).hasSuffix("updates --fond\n"))

        // arreter pendant la mise a jour : la commande s'arrete, sans attendre
        let started = Date()
        let running = Events()
        let task = Task { try await cli.play(id: "3", log: log) { running.add($0) } }
        try await Task.sleep(for: .milliseconds(500))
        #expect(running.states == [.running])
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PlayEvent] = []
    func add(_ value: PlayEvent) { lock.lock(); values.append(value); lock.unlock() }
    var all: [PlayEvent] { lock.lock(); defer { lock.unlock() }; return values }
    /// Les etats de mise a jour vus, dans l'ordre.
    var states: [UpdateStatus.State] {
        all.compactMap { if case let .update(status) = $0 { status.state } else { nil } }
    }
}
