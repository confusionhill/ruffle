import Foundation
import Combine
import FlashPlayerKit

enum PacketDirection: String {
    case client = "C → S"
    case server = "S → C"
}

struct PacketLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let direction: PacketDirection
    let payload: String
}

@MainActor
final class PacketManager: ObservableObject {
    private let bridge: LucentBridge
    private var spamTimer: Timer?
    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    @Published var entries: [PacketLogEntry] = []
    @Published var isPaused = false
    @Published var filterText = ""
    @Published var spamPacket = ""
    @Published var spamIntervalMs = 1000
    @Published var isSpamming = false

    init(bridge: LucentBridge) {
        self.bridge = bridge
    }

    func record(direction: PacketDirection, payload: String) {
        guard !isPaused else { return }
        let entry = PacketLogEntry(
            timestamp: formatter.string(from: Date()),
            direction: direction,
            payload: payload
        )
        entries.append(entry)
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func sendOnce(_ packet: String, toServer: Bool = true) {
        let trimmed = packet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if toServer {
            _ = bridge.sendServerPacket(trimmed)
        } else {
            _ = bridge.sendClientPacket(trimmed)
        }
    }

    func toggleSpam() {
        if isSpamming {
            stopSpam()
        } else {
            startSpam()
        }
    }

    func startSpam() {
        guard !isSpamming else { return }
        isSpamming = true
        let interval = max(0.1, Double(spamIntervalMs) / 1000.0)
        spamTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.sendOnce(self.spamPacket, toServer: true)
            }
        }
    }

    func stopSpam() {
        spamTimer?.invalidate()
        spamTimer = nil
        isSpamming = false
    }
}

struct HttpLogEntry: Identifiable {
    let id: UInt64
    let timestamp: String
    var method: String
    var url: String
    var statusCode: Int
    var bytes: UInt64
    var durationMs: UInt64
    var redirected: Bool = false
    var reqHeaders: [String: String] = [:]
    var reqBody: String?
    var reqMime: String?
    var resBody: String?
    var error: String?

    var statusDisplay: String {
        if statusCode < 0 { return "…" }
        if statusCode == 0 { return "ERR" }
        return "\(statusCode)"
    }

    var sizeDisplay: String {
        if bytes == 0 { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }

    var curlCommand: String {
        var parts = ["curl -X \(method) '\(url)'"]
        for (k, v) in reqHeaders.sorted(by: { $0.key < $1.key }) {
            parts.append("-H '\(k): \(v)'")
        }
        if let mime = reqMime, !mime.isEmpty {
            parts.append("-H 'Content-Type: \(mime)'")
        }
        if let body = reqBody, !body.isEmpty, !body.hasPrefix("<") {
            let escaped = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("--data-raw '\(escaped)'")
        }
        return parts.joined(separator: " \\\n  ")
    }
}

@MainActor
final class HttpLoggerManager: ObservableObject {
    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    @Published var entries: [HttpLogEntry] = []
    @Published var isPaused = false
    @Published var filterText = ""
    @Published var errorsOnly = false
    @Published var showPending = true

    func record(_ event: RuffleHttpLogEvent) {
        if event.phase == "start" {
            guard !isPaused else { return }
            let entry = HttpLogEntry(
                id: event.id,
                timestamp: formatter.string(from: Date()),
                method: event.method ?? "GET",
                url: event.url ?? "",
                statusCode: -1,
                bytes: 0,
                durationMs: 0,
                reqHeaders: event.reqHeaders ?? [:],
                reqBody: event.reqBody,
                reqMime: event.reqMime
            )
            entries.append(entry)
            if entries.count > 1000 {
                entries.removeFirst(entries.count - 1000)
            }
            return
        }

        guard let idx = entries.firstIndex(where: { $0.id == event.id }) else { return }
        switch event.phase {
        case "response":
            if let url = event.url, !url.isEmpty { entries[idx].url = url }
            if let status = event.statusCode { entries[idx].statusCode = status }
            if let bytes = event.bytes, bytes > 0 { entries[idx].bytes = bytes }
            if let ms = event.durationMs { entries[idx].durationMs = ms }
            if let redir = event.redirected { entries[idx].redirected = redir }
        case "body":
            if let bytes = event.bytes, bytes > 0 { entries[idx].bytes = bytes }
            if let body = event.resBody { entries[idx].resBody = body }
        case "error":
            entries[idx].statusCode = 0
            if let url = event.url, !url.isEmpty { entries[idx].url = url }
            if let ms = event.durationMs { entries[idx].durationMs = ms }
            entries[idx].error = event.error
        default:
            break
        }
    }

    func clear() {
        entries.removeAll()
    }
}

@MainActor
final class FollowerManager: ObservableObject {
    private let bridge: LucentBridge
    private var timer: Timer?

    @Published var targetPlayer = ""
    @Published var isFollowing = false

    init(bridge: LucentBridge) {
        self.bridge = bridge
    }

    func toggle() {
        isFollowing ? stop() : start()
    }

    func start() {
        let name = targetPlayer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isFollowing else { return }
        isFollowing = true
        bridge.goToPlayer(name)
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isFollowing, self.bridge.isPlayerLoaded() else { return }
                self.bridge.goToPlayer(name)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isFollowing = false
    }
}

@MainActor
final class AutoReloginManager: ObservableObject {
    private let bridge: LucentBridge
    private var pendingTask: Task<Void, Never>?

    @Published var isEnabled = false
    @Published var username = ""
    @Published var password = ""
    @Published var serverName = "Twilly"
    @Published var delaySeconds = 5
    @Published var servers: [String] = ["Twilly", "Artix", "Galanoth", "Gravelyn", "Sir Ver", "Yorumi"]
    @Published var statusText = "Idle"

    init(bridge: LucentBridge) {
        self.bridge = bridge
    }

    func refreshServers() {
        let list = bridge.getServers()
        let names = list.compactMap { $0["sName"] as? String ?? $0["name"] as? String }
        if !names.isEmpty {
            servers = names
            if !names.contains(serverName), let first = names.first {
                serverName = first
            }
        }
    }

    func handleConnectionEvent(_ event: String) {
        guard isEnabled, event == "OnConnectionLost" else { return }
        guard !username.isEmpty, !password.isEmpty else {
            statusText = "Missing credentials"
            return
        }

        pendingTask?.cancel()
        let delay = max(1, delaySeconds)
        statusText = "Reconnecting in \(delay)s..."

        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self = self, !Task.isCancelled, self.isEnabled else { return }
            self.statusText = "Logging in..."
            _ = self.bridge.login(username: self.username, password: self.password)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, self.isEnabled else { return }
            self.statusText = "Connecting to \(self.serverName)..."
            _ = self.bridge.connectTo(server: self.serverName)
            self.statusText = "Connected"
        }
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        statusText = "Idle"
    }
}

