import Foundation
import Testing

@testable import CidreBridge

/// Les emplacements des jeux Cidre (Cidre 1.5.12) : `cidre emplacements
/// --json`, l'emplacement et l'etat « hors ligne » de chaque jeu dans `cidre
/// list --json`, les evenements de `cidre move --json`, et le refus de lancer
/// un jeu dont le disque est debranche. Les JSON viennent du vrai Cidre
/// (tests/tester_emplacements.sh, sur de faux disques).
struct StorageTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func locations() throws {
        let all = try decode(StorageLocations.self, """
        {"emplacements":[
          {"id":"principal","nom":"Ce Mac","chemin":"/Users/x/Library/Application Support/Cidre/games","volume":null,"en_ligne":true,"defaut":true,"principal":true,"amovible":false,"systeme_fichiers":"apfs","libre":76556201984,"total":994662584320,"inscriptible":true,"jeux":0,"taille_jeux":0,"remarque":null},
          {"id":"jeux-ext-9d71","nom":"Jeux Ext","chemin":"/Volumes/Jeux Ext/Jeux Cidre","volume":"Jeux Ext","en_ligne":true,"defaut":false,"principal":false,"amovible":true,"systeme_fichiers":"exfat","libre":125325312,"total":209387520,"inscriptible":true,"jeux":1,"taille_jeux":1000,"remarque":"exFAT : lisible aussi par Windows."},
          {"id":"vieux-1234","nom":"Vieux","chemin":"/Volumes/Vieux/Jeux Cidre","volume":"Vieux","en_ligne":false,"defaut":false,"principal":false,"amovible":true,"systeme_fichiers":null,"libre":null,"total":null,"inscriptible":null,"jeux":2,"taille_jeux":3000,"remarque":"Debranche : branche le disque « Vieux » pour retrouver ses 2 jeux."},
          {"id":"ntfs-0000","nom":"NTFS","chemin":"/Volumes/NTFS/Jeux Cidre","volume":"NTFS","en_ligne":true,"defaut":false,"principal":false,"amovible":true,"systeme_fichiers":"ntfs","libre":1,"total":2,"inscriptible":false,"jeux":0,"taille_jeux":0,"remarque":"Lecture seule"}
        ],"detectes":[{"chemin":"/Volumes/Autre/Jeux Cidre","id":"autre-beef","volume":"Autre","jeux":3}]}
        """)
        #expect(all.locations.map(\.id) == ["principal", "jeux-ext-9d71", "vieux-1234", "ntfs-0000"])
        let main = all.locations[0]
        #expect(main.isMain && main.isDefault && main.online && !main.removable && main.volume == nil)
        #expect(main.freeBytes == 76_556_201_984 && main.fileSystem == "apfs" && main.acceptsGames)
        let ext = all.locations[1]
        #expect(ext.name == "Jeux Ext" && ext.removable && ext.fileSystem == "exfat" && ext.gameCount == 1 && ext.acceptsGames)
        let unplugged = all.locations[2]
        #expect(!unplugged.online && unplugged.freeBytes == nil && unplugged.writable == nil && !unplugged.acceptsGames)
        #expect(unplugged.gameCount == 2 && unplugged.gamesBytes == 3000 && unplugged.remark?.contains("Vieux") == true)
        #expect(!all.locations[3].acceptsGames)
        #expect(all.detected == [try decode(DetectedLocation.self, #"{"chemin":"/Volumes/Autre/Jeux Cidre","id":"autre-beef","volume":"Autre","jeux":3}"#)])
        #expect(all.detected[0].locationID == "autre-beef" && all.detected[0].gameCount == 3)
    }

    @Test func gameLocationAndOffline() throws {
        let games = try decode([Game].self, """
        [{"id":"111","appid":111,"nom":"Jeu 111","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/Volumes/Jeux Ext/Jeux Cidre/111","taille":1000,"dernier_lancement":0,"emplacement":"jeux-ext-9d71","en_ligne":false,"deplacement":null},
         {"id":"222","appid":222,"nom":"Jeu 222","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/c/222","taille":1,"dernier_lancement":0,"emplacement":"principal","en_ligne":true,"deplacement":{"etat":"en_cours","phase":"copie","de":"principal","vers":"jeux-ext-9d71","avancement":42.5,"octets":425,"total":1000,"raison":null,"message":null}},
         {"id":"333","appid":333,"nom":"Jeu 333","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/c/333","taille":1,"dernier_lancement":0,"emplacement":"principal","en_ligne":true,"deplacement":{"etat":"interrompu","phase":"copie","de":"principal","vers":"jeux-ext-9d71","avancement":null,"octets":null,"total":null,"raison":"interrompu","message":"Deplacement interrompu : rien n'est perdu."}},
         {"id":"444","appid":444,"nom":"Jeu Steam","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"wrapper":null,"chemin":"/s/444","taille":1,"dernier_lancement":0,"emplacement":null,"en_ligne":true,"deplacement":null},
         {"id":"588650","appid":588650,"nom":"Dead Cells","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/c/588650","taille":1,"dernier_lancement":0}]
        """)
        // hors ligne : toujours installe, mais pas jouable
        #expect(games[0].installed && !games[0].online && !games[0].playable && games[0].location == "jeux-ext-9d71")
        // en plein deplacement : pas jouable non plus
        #expect(games[1].online && !games[1].playable && games[1].move?.isRunning == true)
        #expect(games[1].move?.phase == .copie && games[1].move?.to == "jeux-ext-9d71")
        #expect(games[1].move?.progress == DownloadProgress(fraction: 0.425, doneBytes: 425, totalBytes: 1000))
        // deplacement inacheve : le jeu reste jouable la ou il est, a reprendre
        #expect(games[2].playable && games[2].move?.isUnfinished == true && games[2].move?.message?.isEmpty == false)
        #expect(games[3].location == nil && games[3].playable)
        // un Cidre sans emplacements : en ligne, sans deplacement
        #expect(games[4].online && games[4].location == nil && games[4].move == nil && games[4].playable)
    }

    // MARK: Page Stockage

    private func location(_ json: String) throws -> StorageLocation {
        try decode(StorageLocation.self, json)
    }

    @Test func diskUsageFromLocation() throws {
        let main = try location(#"{"id":"principal","nom":"Ce Mac","chemin":"/c","en_ligne":true,"principal":true,"libre":200,"total":1000,"jeux":2,"taille_jeux":300}"#)
        let usage = try #require(DiskUsage(location: main))
        #expect(usage.usedBytes == 800 && usage.gamesBytes == 300 && usage.otherBytes == 500 && usage.freeBytes == 200)
        #expect(abs(usage.gamesFraction + usage.otherFraction + usage.freeFraction - 1) < 1e-9)
        #expect(!usage.isNearlyFull && !usage.summary.isEmpty)
        // la place de macOS (purgeable compris) passe avant le df de Cidre ;
        // les jeux mesures par Verger, s'ils pesent plus que ce que dit Cidre
        let finder = try #require(DiskUsage(location: main, availableBytes: 350, gamesBytes: 400))
        #expect(finder.freeBytes == 350 && finder.gamesBytes == 400 && finder.otherBytes == 250)
        // jamais plus de jeux que d'occupe, ni de libre que de total
        let odd = DiskUsage(totalBytes: 100, freeBytes: 150, gamesBytes: 80)
        #expect(odd.freeBytes == 100 && odd.gamesBytes == 0 && odd.usedBytes == 0)
        #expect(DiskUsage(totalBytes: 1000, freeBytes: 50, gamesBytes: 0).isNearlyFull)
    }

    @Test func unpluggedDiskHasNoBar() throws {
        let unplugged = try location(#"{"id":"vieux","nom":"Vieux","chemin":"/Volumes/Vieux/Jeux Cidre","volume":"Vieux","en_ligne":false,"libre":null,"total":null,"jeux":2,"taille_jeux":3000}"#)
        #expect(DiskUsage(location: unplugged) == nil)
        #expect(DiskUsage(location: unplugged, availableBytes: 10) == nil)
        let unknown = try location(#"{"id":"x","nom":"X","chemin":"/x","en_ligne":true,"libre":null,"total":null}"#)
        #expect(DiskUsage(location: unknown) == nil)
    }

    @Test func gamesOnEachDisk() throws {
        let locations = try decode(StorageLocations.self, """
        {"emplacements":[
          {"id":"principal","nom":"Ce Mac","chemin":"/c","en_ligne":true,"principal":true},
          {"id":"ssd-1","nom":"SSD","chemin":"/Volumes/SSD/Jeux Cidre","volume":"SSD","en_ligne":true},
          {"id":"vieux","nom":"Vieux","chemin":"/Volumes/Vieux/Jeux Cidre","volume":"Vieux","en_ligne":false}
        ]}
        """).locations
        let games = try decode([Game].self, """
        [{"id":"1","appid":1,"nom":"Cidre interne","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"chemin":"/c/1","taille":10,"emplacement":"principal"},
         {"id":"2","appid":2,"nom":"Cidre SSD","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"chemin":"/Volumes/SSD/Jeux Cidre/2","taille":20,"emplacement":"ssd-1"},
         {"id":"3","appid":3,"nom":"Steam SSD","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"chemin":"/Volumes/SSD/SteamLibrary/steamapps/common/3","taille":30},
         {"id":"4","appid":4,"nom":"Steam interne","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"chemin":"/Users/x/Library/Application Support/Steam/steamapps/common/4","taille":40},
         {"id":"local-5","nom":"Hors Steam","plateforme":"windows","lancement":"cidre","source":"local","installe":true,"chemin":"/Volumes/Autre/Jeu/jeu.exe","taille":0},
         {"id":"6","appid":6,"nom":"Debranche","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"chemin":"/Volumes/Vieux/Jeux Cidre/6","taille":60,"emplacement":"vieux","en_ligne":false},
         {"id":"7","appid":7,"nom":"Pas installe","plateforme":"absent","lancement":"cidre","source":"cidre","installe":false,"chemin":"/c/7","taille":0,"emplacement":"principal"}]
        """)
        func ids(_ index: Int) -> [String] { games.filter { locations[index].holds($0, among: locations) }.map(\.id) }
        #expect(ids(0) == ["1", "4"])
        #expect(ids(1) == ["2", "3"])
        // un disque debranche garde ses jeux, grises
        #expect(ids(2) == ["6"])
        // un jeu sur un volume sans emplacement Cidre n'est sur aucun
        #expect(!locations.contains { $0.holds(games[4], among: locations) })
        #expect(StorageLocation.volumeName(of: "/Volumes/SSD/a") == "SSD" && StorageLocation.volumeName(of: "/Users/x") == nil)
    }

    @Test func moveQueueOrderAndCancel() {
        var queue = MoveQueue()
        queue.enqueue(.init(gameID: "1", name: "Un", sizeBytes: 10, to: "ssd"))
        queue.enqueue(.init(gameID: "2", name: "Deux", sizeBytes: 20, to: "ssd"))
        queue.enqueue(.init(gameID: "3", name: "Trois", sizeBytes: 30, to: "principal"))
        // redemande : il garde sa place, change de destination
        queue.enqueue(.init(gameID: "1", name: "Un", sizeBytes: 10, to: "principal"))
        #expect(queue.pending.map(\.gameID) == ["1", "2", "3"] && queue.pending[0].to == "principal")
        #expect(queue.pendingBytes(to: "principal") == 40 && queue.pendingBytes(to: "ssd") == 20)
        queue.cancel("2")
        #expect(!queue.contains("2"))
        #expect(queue.next()?.gameID == "1")
        #expect(queue.pending.map(\.gameID) == ["3"])
        queue.cancelAll()
        #expect(queue.isEmpty && queue.next() == nil)
    }

    @Test func measuredSizeAndCache() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("verger-taille-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sous"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 100_000).write(to: folder.appendingPathComponent("a.bin"))
        try Data(count: 50_000).write(to: folder.appendingPathComponent("sous/b.bin"))
        let size = try #require(GameSizes.measure(folder.path))
        #expect(size >= 150_000)
        #expect(GameSizes.measure(folder.appendingPathComponent("absent").path) == nil)

        // un seul domaine, vide apres chaque passe
        let suite = "io.github.gtranche.verger.tests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(GameSizes.cached("/j", defaults: defaults, now: now) == nil)
        GameSizes.store(1234, for: "/j", defaults: defaults, now: now)
        #expect(GameSizes.cached("/j", defaults: defaults, now: now.addingTimeInterval(3600)) == 1234)
        // au bout d'une semaine, on remesure
        #expect(GameSizes.cached("/j", defaults: defaults, now: now.addingTimeInterval(8 * 24 * 3600)) == nil)
        #expect((GameSizes.importantAvailableCapacity(at: NSHomeDirectory()) ?? 0) > 0)
    }

    @Test func moveEvents() throws {
        let lines = [
            #"{"evenement":"deplacement","etat":"en_cours","phase":"preparation"}"#,
            #"{"evenement":"deplacement","etat":"en_cours","phase":"copie","avancement":0,"octets":0,"total":41943227}"#,
            #"{"evenement":"deplacement","etat":"en_cours","phase":"copie","avancement":52.8,"octets":22146024,"total":41943227}"#,
            #"{"evenement":"deplacement","etat":"en_cours","phase":"verification"}"#,
            #"{"evenement":"deplacement","etat":"fait","emplacement":"faux-exfat-47b5","chemin":"/Volumes/X/Jeux Cidre/222","octets":41943227,"duree":11}"#,
            #"{"evenement":"deplacement","etat":"refuse","raison":"place","message":"Place insuffisante sur « X »."}"#,
            #"{"evenement":"deplacement","etat":"echoue","raison":"debranche","message":"« X » a ete debranche pendant la copie."}"#,
            #"{"evenement":"maj","etat":"verification"}"#,
            "copie : 40 %",
        ]
        let events = lines.map(MoveStatus.parse(line:))
        #expect(events[0]?.state == .running && events[0]?.phase == .preparation && events[0]?.progress == nil)
        #expect(events[1]?.progress == DownloadProgress(fraction: 0, doneBytes: 0, totalBytes: 41_943_227))
        let copying = try #require(events[2]?.progress)
        #expect(abs(copying.fraction - 0.528) < 1e-9 && copying.doneBytes == 22_146_024)
        #expect(events[3]?.phase == .verification && events[3]?.phaseLabel.isEmpty == false)
        #expect(events[4]?.state == .done)
        #expect(events[5]?.state == .refused && events[5]?.reason == "place")
        #expect(events[6]?.state == .failed && events[6]?.isUnfinished == true)
        #expect(events[7] == nil && events[8] == nil)
    }

    @Test func refusedPlayEvent() {
        let line = #"{"evenement":"erreur","code":"hors_ligne","emplacement":"faux-exfat-9d71","message":"Jeu 111 est sur « Faux ExFAT », qui n'est pas branche."}"#
        #expect(PlayEvent.parse(line: line) == .refused(code: "hors_ligne", message: "Jeu 111 est sur « Faux ExFAT », qui n'est pas branche."))
    }

    // MARK: bout en bout, sur une fausse CLI

    @Test func storageCommands() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("cidre")
        try #"""
            #!/bin/sh
            echo "$*" >>"$(dirname "$0")/appels.txt"
            case "$1 $2" in
              "emplacements --json")
                 echo '{"emplacements":[{"id":"principal","nom":"Ce Mac","chemin":"/c","en_ligne":true,"defaut":true,"principal":true,"jeux":0,"taille_jeux":0}],"detectes":[]}' ;;
              "emplacements ajouter")
                 case "$3" in
                   /Volumes/FAT) echo "FAUXFAT est en FAT32 : aucun fichier de plus de 4 Go." >&2; echo '{"erreur":"FAT32"}'; exit 1 ;;
                 esac
                 echo '{"id":"ext-0001","nom":"Ext","chemin":"'"$3"'/Jeux Cidre","volume":"Ext","en_ligne":true,"defaut":false,"principal":false,"amovible":true,"systeme_fichiers":"apfs","libre":10,"total":20,"inscriptible":true,"jeux":0,"taille_jeux":0,"remarque":null}' ;;
              "emplacements retirer"|"emplacements defaut") echo '{}' ;;
              "move 1")
                 echo '{"evenement":"deplacement","etat":"en_cours","phase":"preparation"}'
                 echo "copie de Jeu vers « Ext »" >&2
                 printf '{"evenement":"deplacement","etat":"en_cours","phase":"copie","avancement":50.0,"octets":5,"total":10}\n{"evenement":"deplacement",'
                 sleep 0.2
                 printf '"etat":"en_cours","phase":"verification"}\n{"evenement":"deplacement","etat":"fait","emplacement":"ext-0001","chemin":"/x","octets":10,"duree":1}\n' ;;
              "move 2")
                 echo '{"evenement":"deplacement","etat":"en_cours","phase":"preparation"}'
                 echo '{"evenement":"deplacement","etat":"refuse","raison":"place","message":"Place insuffisante sur « Ext »."}'
                 echo "Place insuffisante sur « Ext »." >&2; exit 5 ;;
              "move 3")
                 echo '{"evenement":"deplacement","etat":"en_cours","phase":"copie","avancement":10,"octets":1,"total":10}'
                 trap 'echo "{\"evenement\":\"deplacement\",\"etat\":\"interrompu\"}"; exit 130' TERM
                 sleep 30 & wait ;;
              "play 9") echo '{"evenement":"erreur","code":"hors_ligne","message":"Jeu 9 est sur « Ext », qui n est pas branche."}'
                 echo "Jeu 9 est sur « Ext »" >&2; exit 8 ;;
              "emplacements"*|"move"*) exit 2 ;;
              *) echo "cidre — launcher Cidre" ;;
            esac
            """#.write(to: script, atomically: true, encoding: .utf8)
        let cli = CidreCLI(executable: script)
        let calls = dir.appendingPathComponent("appels.txt")

        let found = try #require(try await cli.storageLocations())
        #expect(found.locations.map(\.id) == ["principal"] && found.detected.isEmpty)

        let added = try await cli.addStorageLocation(URL(fileURLWithPath: "/Volumes/Ext"))
        #expect(added.id == "ext-0001" && added.path == "/Volumes/Ext/Jeux Cidre")
        // un refus de Cidre : sa phrase, telle quelle
        await #expect(throws: CidreError.refused(message: "FAUXFAT est en FAT32 : aucun fichier de plus de 4 Go.")) {
            try await cli.addStorageLocation(URL(fileURLWithPath: "/Volumes/FAT"))
        }
        try await cli.setDefaultStorageLocation(id: "ext-0001")
        try await cli.removeStorageLocation(id: "ext-0001")

        // un deplacement qui aboutit : les evenements dans l'ordre, meme coupes en deux
        let seen = MoveEvents()
        try await cli.move(id: "1", to: "ext-0001") { seen.add($0) }
        #expect(seen.all.map(\.state) == [.running, .running, .running, .done])
        #expect(seen.all.compactMap(\.phase) == [.preparation, .copie, .verification])
        #expect(seen.all[1].progress == DownloadProgress(fraction: 0.5, doneBytes: 5, totalBytes: 10))
        // refuse (code 5) : la phrase de Cidre
        await #expect(throws: CidreError.refused(message: "Place insuffisante sur « Ext ».")) {
            try await cli.move(id: "2", to: "ext-0001") { _ in }
        }
        // arreter : la commande s'arrete sans attendre, et c'est une annulation
        let started = Date()
        let running = MoveEvents()
        let task = Task { try await cli.move(id: "3", to: "ext-0001") { running.add($0) } }
        try await Task.sleep(for: .milliseconds(500))
        #expect(running.all.first?.state == .running)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 10)

        // un jeu dont le disque est debranche ne part pas : la phrase de Cidre
        await #expect(throws: CidreError.refused(message: "Jeu 9 est sur « Ext », qui n est pas branche.")) {
            try await cli.play(id: "9", log: dir.appendingPathComponent("play.log")) { _ in }
        }
        #expect(try String(contentsOf: calls, encoding: .utf8) == """
            emplacements --json
            emplacements ajouter /Volumes/Ext --json
            emplacements ajouter /Volumes/FAT --json
            emplacements defaut ext-0001 --json
            emplacements retirer ext-0001 --json
            move 1 ext-0001 --json
            move 2 ext-0001 --json
            move 3 ext-0001 --json
            play 9 --json

            """)
    }

    /// Un Cidre d'avant les emplacements repond par son mode d'emploi : pas
    /// d'erreur, mais pas d'emplacements non plus.
    @Test func olderCidreHasNoLocations() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("cidre")
        try "#!/bin/sh\necho 'cidre — launcher Cidre (jeux Steam ou non, natifs ou via Cidre)'\n"
            .write(to: script, atomically: true, encoding: .utf8)
        #expect(try await CidreCLI(executable: script).storageLocations() == nil)
    }

    /// Les disques, comme sur une console : ce Mac, les disques branches (connus
    /// de Cidre ou non), puis les debranches ; un dossier de ce Mac n'en est pas un.
    @Test func disks() throws {
        let locations = try decode([StorageLocation].self, """
        [{"id":"principal","nom":"Ce Mac","chemin":"/Users/x/Cidre/games","volume":null,"en_ligne":true,"defaut":false,"principal":true,"libre":100,"total":1000,"inscriptible":true,"jeux":5,"taille_jeux":50},
         {"id":"ssk-ssd-eaef","nom":"SSK SSD","chemin":"/Volumes/SSK SSD/Jeux Cidre","volume":"SSK SSD","en_ligne":true,"defaut":true,"principal":false,"libre":350,"total":500,"inscriptible":true,"jeux":2,"taille_jeux":118},
         {"id":"vieux-1234","nom":"Vieux","chemin":"/Volumes/Vieux/Jeux Cidre","volume":"Vieux","en_ligne":false,"principal":false,"jeux":2,"taille_jeux":3000},
         {"id":"jeux-abcd","nom":"~/Jeux","chemin":"/Users/x/Jeux","volume":null,"en_ligne":true,"principal":false,"jeux":1,"taille_jeux":1}]
        """)
        let mounted = [
            MountedVolume(name: "Clé", path: "/Volumes/Clé", freeBytes: 64, totalBytes: 128),
            MountedVolume(name: "SSK SSD", path: "/Volumes/SSK SSD", freeBytes: 351, totalBytes: 500),
        ]
        let disks = GameDisk.list(locations: locations, mounted: mounted)
        #expect(disks.map(\.id) == ["principal", "volume:/Volumes/Clé", "ssk-ssd-eaef", "vieux-1234"])
        #expect(disks[0].kind == .thisMac && disks[0].symbol == "internaldrive")
        // un disque nouveau : pas d'emplacement, mais sa place libre
        #expect(disks[1].isNew && disks[1].online && disks[1].acceptsGames && disks[1].freeBytes == 64)
        #expect(disks[1].volume?.path == "/Volumes/Clé")
        #expect(disks[2].isDefault && disks[2].freeBytes == 350 && disks[2].kind == .external)
        #expect(!disks[3].online && !disks[3].acceptsGames && disks[3].symbol == "externaldrive.badge.xmark")
        #expect(disks[3].label.contains("Vieux"))

        let games = try decode([Game].self, """
        [{"id":"1137300","appid":1137300,"nom":"Sherlock","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"chemin":"/Users/x/Cidre/games/1137300","emplacement":"principal"},
         {"id":"1245620","appid":1245620,"nom":"Elden","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"chemin":"/Volumes/SSK SSD/Jeux Cidre/1245620","emplacement":"ssk-ssd-eaef"},
         {"id":"local-x","nom":"X","plateforme":"windows","lancement":"cidre","source":"local","installe":true,"chemin":"/Volumes/Clé/X"}]
        """)
        #expect(GameDisk.of(games[0], among: disks)?.id == "principal")
        #expect(GameDisk.of(games[1], among: disks)?.id == "ssk-ssd-eaef")
        #expect(GameDisk.of(games[2], among: disks)?.id == "volume:/Volumes/Clé")
    }

    /// Deux emplacements sur un meme volume : le disque prend celui par defaut.
    @Test func diskWithTwoLocations() throws {
        let locations = try decode([StorageLocation].self, """
        [{"id":"principal","nom":"Ce Mac","chemin":"/a","en_ligne":true,"principal":true},
         {"id":"ssd-1","nom":"SSD","chemin":"/Volumes/SSD/Jeux Cidre","volume":"SSD","en_ligne":true},
         {"id":"ssd-2","nom":"SSD","chemin":"/Volumes/SSD/Autres","volume":"SSD","en_ligne":true,"defaut":true}]
        """)
        let disks = GameDisk.list(locations: locations, mounted: [MountedVolume(name: "SSD", path: "/Volumes/SSD")])
        #expect(disks.map(\.id) == ["principal", "ssd-2"])
    }
}

private final class MoveEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MoveStatus] = []
    func add(_ value: MoveStatus) { lock.lock(); values.append(value); lock.unlock() }
    var all: [MoveStatus] { lock.lock(); defer { lock.unlock() }; return values }

}
