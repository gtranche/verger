import Foundation
import Testing

@testable import CidreBridge

/// Un faux Discord : un socket local qui parle son protocole et note ce qu'il recoit.
private final class FakeDiscord: @unchecked Sendable {
    let directory: URL
    private let listener: Int32
    private let lock = NSLock()
    private var messages: [(opcode: UInt32, json: [String: Any])] = []
    private var closed = false

    /// `refuse` : repondre a la presentation par une fermeture, comme Discord
    /// le fait pour un identifiant d'application inconnu.
    init(refuse: Bool = false) throws {
        // un chemin court : celui d'un socket ne depasse pas 104 octets
        directory = URL(fileURLWithPath: "/tmp/vg-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("discord-ipc-0").path
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 1) == 0 else { throw CocoaError(.fileWriteUnknown) }
        Thread.detachNewThread { [self] in serve(refuse: refuse) }
    }

    deinit {
        Darwin.close(listener)
        try? FileManager.default.removeItem(at: directory)
    }

    var received: [(opcode: UInt32, json: [String: Any])] { lock.lock(); defer { lock.unlock() }; return messages }
    var clientClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    private func serve(refuse: Bool) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        func read(_ count: Int) -> Data? {
            var data = Data(count: count), done = 0
            while done < count {
                let n = data.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress! + done, count - done) }
                if n <= 0 { return nil }
                done += n
            }
            return data
        }
        func reply(_ opcode: DiscordPresence.Opcode, _ json: [String: Any]) {
            let data = try! DiscordPresence.frame(opcode, json)
            _ = data.withUnsafeBytes { write(client, $0.baseAddress, data.count) }
        }
        while let header = read(8) {
            let opcode = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
            let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
            guard let body = read(Int(length)),
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { break }
            lock.lock(); messages.append((opcode, json)); lock.unlock()
            if opcode == 0 {
                if refuse {
                    reply(.close, ["code": 4000, "message": "Invalid Client ID"])
                    return
                }
                reply(.frame, ["cmd": "DISPATCH", "evt": "READY", "data": ["v": 1]])
            } else if json["cmd"] as? String == "SET_ACTIVITY" {
                reply(.frame, ["cmd": "SET_ACTIVITY", "evt": NSNull(), "nonce": json["nonce"] ?? "", "data": [:]])
            }
        }
        lock.lock(); closed = true; lock.unlock()
    }
}

@Test func afficheLeJeuSurDiscord() async throws {
    let discord = try FakeDiscord()
    let presence = DiscordPresence(applicationID: "123456789", directory: discord.directory)
    let start = Date(timeIntervalSince1970: 1_791_000_000)

    try await presence.show(since: start)
    #expect(await presence.isConnected)

    let received = discord.received
    #expect(received.count == 2)
    // la presentation, puis l'activite
    #expect(received[0].opcode == 0)
    #expect(received[0].json["client_id"] as? String == "123456789")
    #expect(received[0].json["v"] as? Int == 1)
    #expect(received[1].opcode == 1)
    #expect(received[1].json["cmd"] as? String == "SET_ACTIVITY")
    let args = try #require(received[1].json["args"] as? [String: Any])
    #expect(args["pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier))
    let activity = try #require(args["activity"] as? [String: Any])
    #expect(activity["type"] as? Int == 0)
    #expect((activity["timestamps"] as? [String: Any])?["start"] as? Int == 1_791_000_000)
    // ni nom ni image : Discord les tire de l'identifiant du jeu
    #expect(Set(activity.keys) == ["type", "timestamps"])

    // redire l'annonce reutilise la connexion : pas de nouvelle presentation
    try await presence.show(since: start)
    #expect(discord.received.count == 3)
    #expect(discord.received[2].opcode == 1)

    // effacer = fermer la connexion ; Discord retire alors l'activite
    await presence.clear()
    #expect(await !presence.isConnected)
    for _ in 0..<50 where !discord.clientClosed { try await Task.sleep(for: .milliseconds(20)) }
    #expect(discord.clientClosed)
}

@Test func discordFermeOuIdentifiantRefuse() async throws {
    // Discord n'est pas ouvert : aucun socket
    let empty = URL(fileURLWithPath: "/tmp/vg-\(UUID().uuidString.prefix(8))")
    let absent = DiscordPresence(applicationID: "1", directory: empty)
    await #expect(throws: DiscordPresence.Failure.discordNotRunning) {
        try await absent.show(since: Date())
    }

    // identifiant d'application refuse : l'erreur porte la raison, la connexion est abandonnee
    let discord = try FakeDiscord(refuse: true)
    let presence = DiscordPresence(applicationID: "0", directory: discord.directory)
    await #expect(throws: DiscordPresence.Failure.refused("Invalid Client ID")) {
        try await presence.show(since: Date())
    }
    #expect(await !presence.isConnected)
    #expect(discord.received.count == 1)   // rien n'a ete envoye apres le refus
}

/// Le vrai Discord de cette machine, sans rien publier : on se presente avec un
/// identifiant d'application qui n'existe pas, et on attend son refus. Verifie
/// le socket et le protocole.
///   VERGER_ESSAI_DISCORD=1 Scripts/test.sh --filter leVraiDiscordRepond
@Test(.enabled(if: ProcessInfo.processInfo.environment["VERGER_ESSAI_DISCORD"] != nil))
func leVraiDiscordRepond() async {
    let presence = DiscordPresence(applicationID: "0")
    do {
        try await presence.show(since: Date())
        Issue.record("un identifiant inexistant aurait du etre refuse")
    } catch let DiscordPresence.Failure.refused(reason) {
        print("Discord a refuse l'identifiant inexistant : \(reason)")
    } catch {
        Issue.record("reponse inattendue : \(error)")
    }
}

@Test func catalogueDesJeuxDeDiscord() async throws {
    let liste = """
        [{"id":"111","name":"Dead Cells","aliases":[],"third_party_skus":[{"distributor":"epic","id":"X"},{"distributor":"steam","id":"588650"}],"executables":[{"os":"win32","name":"deadcells.exe"}]},
         {"id":"222","name":"Rainbow Six Siege","aliases":["Tom Clancy's Rainbow Six® Siege"],"third_party_skus":[]},
         {"id":"333","name":"Siege","aliases":["Rainbow Six Siege"],"third_party_skus":null}]
        """
    let catalog = try DiscordCatalog.parse(Data(liste.utf8))
    #expect(catalog.count == 3)
    // par l'appid Steam, quel que soit le nom
    #expect(catalog.applicationID(name: "N'importe quoi", steamAppID: 588650) == "111")
    // par le nom, sans casse ni ponctuation ; puis par un alias
    #expect(catalog.applicationID(name: "DEAD  CELLS!", steamAppID: nil) == "111")
    #expect(catalog.applicationID(name: "Tom Clancy's Rainbow Six Siege", steamAppID: 42) == "222")
    // un alias ne prend pas la place du nom d'un autre jeu
    #expect(catalog.applicationID(name: "Rainbow Six Siege", steamAppID: nil) == "222")
    #expect(catalog.applicationID(name: "Jeu inconnu", steamAppID: 7) == nil)

    // charge depuis la source, mis en cache, puis relu du cache sans la source
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("liste.json"), cache = dir.appendingPathComponent("cache/jeux.json")
    try liste.write(to: source, atomically: true, encoding: .utf8)
    #expect(await DiscordCatalog.load(cache: cache, source: source) == catalog)
    try FileManager.default.removeItem(at: source)
    #expect(await DiscordCatalog.load(cache: cache, source: source) == catalog)
    // cache perime et source injoignable : l'ancien cache sert encore
    #expect(await DiscordCatalog.load(cache: cache, maxAge: 0, source: source) == catalog)
    // ni cache ni source : rien
    #expect(await DiscordCatalog.load(cache: dir.appendingPathComponent("absent.json"), source: source) == nil)
}

/// La vraie liste de Discord (13 Mo telecharges) : elle se lit, et connait des
/// jeux courants par leur appid Steam.
///   VERGER_ESSAI_DISCORD=1 Scripts/test.sh --filter laVraieListeDeDiscord
@Test(.enabled(if: ProcessInfo.processInfo.environment["VERGER_ESSAI_DISCORD"] != nil))
func laVraieListeDeDiscord() async throws {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cache) }
    let started = Date()
    let catalog = try #require(await DiscordCatalog.load(cache: cache))
    let size = (try? FileManager.default.attributesOfItem(atPath: cache.path)[.size] as? Int) ?? 0
    print("catalogue : \(catalog.count) jeux en \(String(format: "%.1f", Date().timeIntervalSince(started))) s, cache de \(size / 1024) Kio")
    #expect(catalog.count > 10_000)
    for (name, appid) in [("Dead Cells", 588650), ("Warhammer: Vermintide 2", 552500), ("DREDGE", 1562430), ("Surviving Mars", 464920)] {
        let bySteam = catalog.applicationID(name: "", steamAppID: appid)
        let byName = catalog.applicationID(name: name, steamAppID: nil)
        print("  \(name) : \(bySteam ?? "inconnu par appid"), \(byName == bySteam ? "meme identifiant par le nom" : "par le nom : \(byName ?? "inconnu")")")
        #expect(bySteam != nil)
    }
}
