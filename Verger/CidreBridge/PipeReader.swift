import Foundation

/// Lit la sortie d'une commande au fil de l'eau, puis jusqu'au bout quand elle
/// se termine.
///
/// Un processus peut ecrire sa derniere ligne et sortir aussitot : sa fin nous
/// est annoncee avant que cette ligne n'ait ete lue. Sans `finish()`, on perdait
/// alors le dernier avancement d'un telechargement, la fin d'un message
/// d'erreur, ou la ligne qui dit qu'une connexion a reussi.
final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private let onData: @Sendable (Data) -> Void

    /// `onData` recoit les morceaux dans l'ordre, un seul a la fois.
    init(_ pipe: Pipe, onData: @escaping @Sendable (Data) -> Void) {
        handle = pipe.fileHandleForReading
        self.onData = onData
        // Lecture non bloquante : vider le tube a la fin ne doit pas attendre
        // un petit-fils du processus qui le garderait ouvert.
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        handle.readabilityHandler = { [weak self] handle in
            if self?.pump() ?? true { handle.readabilityHandler = nil }
        }
    }

    /// Lit ce qui est disponible ; rend vrai une fois le tube ferme.
    @discardableResult
    private func pump() -> Bool {
        lock.lock(); defer { lock.unlock() }
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(handle.fileDescriptor, &buffer, buffer.count)
            if n > 0 {
                onData(Data(buffer[0..<n]))
            } else if n == 0 {
                return true
            } else if errno != EINTR {
                return false   // rien de plus pour l'instant
            }
        }
    }

    /// A appeler quand le processus est termine : on lit ce qu'il a laisse.
    func finish() {
        handle.readabilityHandler = nil
        pump()
    }
}
