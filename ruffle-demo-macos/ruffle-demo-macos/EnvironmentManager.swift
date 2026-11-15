import Foundation
import Combine
import SwiftUI

struct RegisteredQuest: Identifiable, Codable, Equatable {
    var id: Int { questId }
    var questId: Int
    var rewardItemId: Int?
}

@MainActor
final class EnvironmentManager: ObservableObject {
    private let bridge: LucentBridge
    private var timer: Timer?

    // Drops
    @Published var dropsEnabled = false { didSet { syncTimer() } }
    @Published var rejectUnregisteredDrops = false
    @Published var whitelistItems: [String] = []
    private(set) var pendingDrops: [Int: String] = [:] // itemId -> itemName

    // Quests
    @Published var questsEnabled = false { didSet { syncTimer() } }
    @Published var registeredQuests: [RegisteredQuest] = []

    // Boosts
    @Published var boostsEnabled = false { didSet { syncTimer() } }
    @Published var registeredBoosts: [String] = []

    init(bridge: LucentBridge) {
        self.bridge = bridge
    }

    func addDropItem(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !whitelistItems.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        whitelistItems.append(trimmed)
    }

    func removeDropItem(at offsets: IndexSet) {
        whitelistItems.remove(atOffsets: offsets)
    }

    func addQuest(id: Int, rewardId: Int?) {
        guard id > 0, !registeredQuests.contains(where: { $0.questId == id }) else { return }
        registeredQuests.append(RegisteredQuest(questId: id, rewardItemId: rewardId))
    }

    func removeQuest(at offsets: IndexSet) {
        registeredQuests.remove(atOffsets: offsets)
    }

    func addBoost(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !registeredBoosts.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        registeredBoosts.append(trimmed)
    }

    func removeBoost(at offsets: IndexSet) {
        registeredBoosts.remove(atOffsets: offsets)
    }

    private func syncTimer() {
        let anyEnabled = dropsEnabled || questsEnabled || boostsEnabled
        if anyEnabled && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
        } else if !anyEnabled {
            timer?.invalidate()
            timer = nil
        }
    }

    func handleExtensionResponse(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = json["cmd"] as? String,
              cmd == "dropItem",
              let items = json["items"] as? [String: [String: Any]] else {
            return
        }

        for (key, info) in items {
            let itemId = (info["ItemID"] as? Int)
                ?? (info["ItemID"] as? String).flatMap(Int.init)
                ?? Int(key)
            let name = (info["sName"] as? String) ?? ""
            guard let id = itemId, !name.isEmpty else { continue }
            pendingDrops[id] = name
        }

        if dropsEnabled {
            processPendingDrops()
        }
    }

    func findPendingDropId(matching query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed), pendingDrops[id] != nil {
            return id
        }
        return pendingDrops.first(where: { $0.value.caseInsensitiveCompare(trimmed) == .orderedSame })?.key
    }

    func acceptDropByNameOrId(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) {
            let ok = bridge.acceptDrop(itemId: id)
            if ok { pendingDrops.removeValue(forKey: id) }
            return ok
        }
        guard let id = findPendingDropId(matching: trimmed) else { return false }
        let ok = bridge.acceptDrop(itemId: id)
        if ok { pendingDrops.removeValue(forKey: id) }
        return ok
    }

    func rejectDropByNameOrId(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) {
            let ok = bridge.rejectDrop(itemId: id)
            if ok { pendingDrops.removeValue(forKey: id) }
            return ok
        }
        guard let id = findPendingDropId(matching: trimmed) else { return false }
        let ok = bridge.rejectDrop(itemId: id)
        if ok { pendingDrops.removeValue(forKey: id) }
        return ok
    }

    private func processPendingDrops() {
        guard bridge.isPlayerLoaded() else { return }
        for (id, name) in pendingDrops {
            let isWhitelisted = whitelistItems.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            if isWhitelisted {
                if bridge.acceptDrop(itemId: id) {
                    pendingDrops.removeValue(forKey: id)
                }
            } else if rejectUnregisteredDrops {
                if bridge.rejectDrop(itemId: id) {
                    pendingDrops.removeValue(forKey: id)
                }
            }
        }
    }

    private func tick() {
        guard bridge.isPlayerLoaded() else { return }

        if dropsEnabled {
            processPendingDrops()
        }

        if questsEnabled {
            for quest in registeredQuests {
                if !bridge.callBool("quests.isInProgress", args: [quest.questId]) {
                    _ = bridge.acceptQuest(quest.questId)
                } else if bridge.canCompleteQuest(quest.questId) {
                    _ = bridge.completeQuest(quest.questId, rewardId: quest.rewardItemId ?? -1)
                }
            }
        }

        if boostsEnabled {
            for boost in registeredBoosts {
                let lower = boost.lowercased()
                let typeKey: String
                if lower.contains("gold") { typeKey = "gold" }
                else if lower.contains("class") { typeKey = "cp" }
                else if lower.contains("rep") { typeKey = "rep" }
                else { typeKey = "xp" }

                if !bridge.hasActiveBoost(typeKey) {
                    _ = bridge.useInventoryItem(boost)
                }
            }
        }
    }
}
