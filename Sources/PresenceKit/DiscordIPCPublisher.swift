import Darwin
import Foundation
import PresenceCore

/// One message of Discord's local IPC protocol: little-endian opcode and length, then JSON.
struct DiscordFrame: Equatable {
    static let handshake: Int32 = 0
    static let frame: Int32 = 1
    static let close: Int32 = 2

    var opcode: Int32
    var payload: Data

    static func encode(opcode: Int32, payload: Data) -> Data {
        var data = Data(capacity: 8 + payload.count)
        withUnsafeBytes(of: opcode.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }
}

/// Reassembles frames from a byte stream that may split or merge them arbitrarily.
struct DiscordFrameBuffer {
    private var pending = Data()

    mutating func append(_ chunk: some DataProtocol) -> [DiscordFrame] {
        pending.append(contentsOf: chunk)
        var frames: [DiscordFrame] = []
        while pending.count >= 8 {
            let header = [UInt8](pending.prefix(8))
            let opcode = header[0..<4].withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) }
            let length = Int(header[4..<8].withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) })
            guard pending.count >= 8 + length else { break }
            frames.append(DiscordFrame(opcode: opcode, payload: Data(pending.dropFirst(8).prefix(length))))
            pending = Data(pending.dropFirst(8 + length))
        }
        return frames
    }
}

public enum DiscordIPCError: Error, LocalizedError {
    case notRunning
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Discord is not running"
        case let .rejected(message): "Discord rejected the connection: \(message)"
        }
    }
}

/// Talks to the local Discord desktop client over its IPC unix socket.
public final class DiscordIPCPublisher: PresencePublisher, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.discord-apple-music.ipc")
    private var socket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var clientID: String

    /// Called (on a background queue) when an established connection drops.
    public var onDisconnect: (@Sendable () -> Void)?

    public init(clientID: String) {
        self.clientID = clientID
    }

    /// Switching applications requires a new handshake.
    public func setClientID(_ id: String) {
        queue.sync {
            guard id != clientID else { return }
            clientID = id
            closeLocked(notify: false)
        }
    }

    public func publish(_ activity: Activity?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.connectIfNeededLocked()
                    try self.sendLocked(opcode: DiscordFrame.frame, payload: Self.setActivityPayload(activity))
                    continuation.resume()
                } catch {
                    self.closeLocked(notify: false)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func close() {
        queue.sync { closeLocked(notify: false) }
    }

    static func setActivityPayload(_ activity: Activity?) throws -> Data {
        struct Args: Encodable {
            var pid: Int32
            /// Omitted (not null) when clearing, which is what Discord expects.
            var activity: Activity?
        }
        struct Command: Encodable {
            var cmd = "SET_ACTIVITY"
            var nonce = UUID().uuidString
            var args: Args
        }
        return try JSONEncoder().encode(Command(args: Args(pid: getpid(), activity: activity)))
    }

    // MARK: - Socket handling (always on `queue`)

    private func connectIfNeededLocked() throws {
        guard socket < 0 else { return }
        // NSTemporaryDirectory() is the per-user temp dir Discord uses, even under launchd.
        let directory = NSTemporaryDirectory()
        for index in 0..<10 {
            let path = (directory as NSString).appendingPathComponent("discord-ipc-\(index)")
            guard let fd = Self.connectUnixSocket(path) else { continue }
            do {
                try handshake(fd)
            } catch DiscordIPCError.rejected(let message) {
                Darwin.close(fd)
                throw DiscordIPCError.rejected(message)
            } catch {
                Darwin.close(fd)
                continue
            }
            socket = fd
            startReading(fd)
            return
        }
        throw DiscordIPCError.notRunning
    }

    private static func connectUnixSocket(_ path: String) -> Int32? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { Darwin.close(fd); return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { Darwin.close(fd); return nil }
        return fd
    }

    /// Sends the handshake and blocks (up to the receive timeout) until Discord answers READY.
    private func handshake(_ fd: Int32) throws {
        let hello = try JSONSerialization.data(withJSONObject: ["v": 1, "client_id": clientID])
        try Self.writeAll(fd, DiscordFrame.encode(opcode: DiscordFrame.handshake, payload: hello))

        var buffer = DiscordFrameBuffer()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { throw DiscordIPCError.notRunning }
            for frame in buffer.append(chunk[0..<count]) {
                let json = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any]
                if frame.opcode == DiscordFrame.close {
                    throw DiscordIPCError.rejected(json?["message"] as? String ?? "closed")
                }
                if json?["evt"] as? String == "READY" { return }
            }
        }
    }

    private func startReading(_ fd: Int32) {
        var buffer = DiscordFrameBuffer()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { return self.closeLocked(notify: true) }
            for frame in buffer.append(chunk[0..<count]) {
                if frame.opcode == DiscordFrame.close { return self.closeLocked(notify: true) }
                if let json = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any],
                   json["evt"] as? String == "ERROR"
                {
                    NSLog("[discord] command failed: %@", String(describing: json["data"] ?? json))
                }
            }
        }
        readSource = source
        source.resume()
    }

    private func sendLocked(opcode: Int32, payload: Data) throws {
        guard socket >= 0 else { throw DiscordIPCError.notRunning }
        try Self.writeAll(socket, DiscordFrame.encode(opcode: opcode, payload: payload))
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard written > 0 else { throw DiscordIPCError.notRunning }
                offset += written
            }
        }
    }

    private func closeLocked(notify: Bool) {
        guard socket >= 0 else { return }
        readSource?.cancel() // closing the fd while the source is active is undefined
        readSource = nil
        Darwin.close(socket)
        socket = -1
        if notify { onDisconnect?() }
    }
}
