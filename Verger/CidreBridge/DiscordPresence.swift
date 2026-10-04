import Foundation

/// Le jeu en cours, affiche dans le profil Discord de l'utilisateur (« Rich
/// Presence »). Discord tourne sur le Mac et ecoute sur un socket local,
/// `$TMPDIR/discord-ipc-0` ; on s'y presente au nom d'une application Discord
/// (son identifiant est public) et on lui dit a quoi on joue. Rien ne passe
/// par le reseau de notre cote : c'est le client Discord qui publie.
///
/// L'activite vit tant que la connexion reste ouverte : la fermer l'efface.
public actor DiscordPresence {
    public struct Activity: Equatable, Sendable {
        /// Le nom du jeu.
        public var name: String
        public var start: Date
        /// Une illustration du jeu (adresse https), facultative.
        public var image: URL?

        public init(name: String, start: Date, image: URL? = nil) {
            self.name = name
            self.start = start
            self.image = image
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        /// Aucun socket : Discord n'est pas ouvert.
        case discordNotRunning
        /// Discord a ferme la connexion (identifiant d'application refuse, par exemple).
        case refused(String)
        case connectionLost
    }

    private let applicationID: String
    private let directory: URL
    private var socket: Int32 = -1

    public init(applicationID: String, directory: URL = URL(fileURLWithPath: NSTemporaryDirectory())) {
        self.applicationID = applicationID
        self.directory = directory
    }

    /// Affiche l'activite ; se connecte a Discord si ce n'est pas deja fait.
    public func show(_ activity: Activity) throws {
        do {
            try connect()
            try send(opcode: .frame, Self.setActivity(activity, pid: ProcessInfo.processInfo.processIdentifier))
            _ = try receive()
        } catch {
            close()
            throw error
        }
    }

    /// Efface l'activite : on ferme la connexion, Discord fait le reste.
    public func clear() {
        close()
    }

    public var isConnected: Bool { socket >= 0 }

    // MARK: Messages

    enum Opcode: UInt32 {
        case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4
    }

    static func handshake(applicationID: String) -> [String: Any] {
        ["v": 1, "client_id": applicationID]
    }

    static func setActivity(_ activity: Activity, pid: Int32) -> [String: Any] {
        var payload: [String: Any] = [
            "type": 0,   // « Joue a »
            "details": activity.name,
            "timestamps": ["start": Int(activity.start.timeIntervalSince1970)],
            // Dans la liste des membres, afficher le nom du jeu (le champ
            // `details`) plutot que celui de l'application Discord.
            "status_display_type": 2,
        ]
        if let image = activity.image {
            payload["assets"] = ["large_image": image.absoluteString, "large_text": activity.name]
        }
        return [
            "cmd": "SET_ACTIVITY",
            "nonce": UUID().uuidString,
            "args": ["pid": Int(pid), "activity": payload],
        ]
    }

    /// Un message du protocole : code (4 octets), longueur (4 octets), puis JSON.
    static func frame(_ opcode: Opcode, _ json: [String: Any]) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json)
        var data = Data()
        withUnsafeBytes(of: opcode.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(body)
        return data
    }

    // MARK: Connexion

    private func connect() throws {
        guard socket < 0 else { return }
        // Discord numerote ses sockets de 0 a 9 (plusieurs clients ouverts).
        for index in 0..<10 {
            let path = directory.appendingPathComponent("discord-ipc-\(index)").path
            guard FileManager.default.fileExists(atPath: path), let fd = Self.open(path) else { continue }
            socket = fd
            try send(opcode: .handshake, Self.handshake(applicationID: applicationID))
            _ = try receive()   // READY, ou une fermeture si l'identifiant est refuse
            return
        }
        throw Failure.discordNotRunning
    }

    private func close() {
        if socket >= 0 { Darwin.close(socket) }
        socket = -1
    }

    private static func open(_ path: String) -> Int32? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // Ecrire sur une connexion fermee par Discord ne doit pas tuer Verger.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        // Ni attendre indefiniment un Discord qui ne repond pas.
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { Darwin.close(fd); return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
        }
        guard connected == 0 else { Darwin.close(fd); return nil }
        return fd
    }

    private func send(opcode: Opcode, _ json: [String: Any]) throws {
        let data = try Self.frame(opcode, json)
        let written = data.withUnsafeBytes { Darwin.write(socket, $0.baseAddress, data.count) }
        guard written == data.count else { throw Failure.connectionLost }
    }

    private func read(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var done = 0
        while done < count {
            let n = data.withUnsafeMutableBytes { Darwin.read(socket, $0.baseAddress! + done, count - done) }
            guard n > 0 else { throw Failure.connectionLost }
            done += n
        }
        return data
    }

    /// Le prochain message de Discord. Une fermeture devient une erreur qui
    /// porte la raison qu'il donne.
    private func receive() throws -> [String: Any] {
        let header = try read(8)
        let opcode = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        guard length < 1 << 20 else { throw Failure.connectionLost }
        let body = try read(Int(length))
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if opcode == Opcode.close.rawValue {
            throw Failure.refused(json["message"] as? String ?? "")
        }
        // Une commande refusee revient en « evt: ERROR ».
        if json["evt"] as? String == "ERROR" {
            let detail = (json["data"] as? [String: Any])?["message"] as? String
            throw Failure.refused(detail ?? "")
        }
        return json
    }
}
