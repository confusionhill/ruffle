import Foundation
import Combine
import FlashPlayerKit

@MainActor
final class LucentBridge: ObservableObject {
    weak var player: RufflePlayer?

    @Published var isGameLoaded = false
    @Published var connectionStatus = "Disconnected"
    @Published var lastProgress: Int = 0

    var onPacketFromClient: ((String) -> Void)?
    var onPacketFromServer: ((String) -> Void)?
    var onConnectionEvent: ((String) -> Void)?
    var onExtensionResponse: ((String) -> Void)?

    // MARK: - Low-level ExternalInterface Helpers

    @discardableResult
    func call(_ name: String, args: [Any] = []) -> Any? {
        player?.callExternalInterface(name: name, arguments: args)
    }

    func callBool(_ name: String, args: [Any] = []) -> Bool {
        guard let res = call(name, args: args) else { return false }
        if let b = res as? Bool { return b }
        if let n = res as? NSNumber { return n.boolValue }
        if let s = res as? String { return (s as NSString).boolValue || s.lowercased() == "true" }
        return false
    }

    func callInt(_ name: String, args: [Any] = []) -> Int {
        guard let res = call(name, args: args) else { return 0 }
        if let i = res as? Int { return i }
        if let d = res as? Double { return Int(d) }
        if let s = res as? String, let i = Int(s) { return i }
        return 0
    }

    func callString(_ name: String, args: [Any] = []) -> String {
        guard let res = call(name, args: args) else { return "" }
        if let s = res as? String { return s }
        return "\(res)"
    }

    func callJSON(_ name: String, args: [Any] = []) -> Any? {
        guard let res = call(name, args: args) else { return nil }
        if let s = res as? String, let data = s.data(using: .utf8) {
            return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) ?? s
        }
        return res
    }

    func callStringArray(_ name: String, args: [Any] = []) -> [String] {
        guard let obj = callJSON(name, args: args) else { return [] }
        if let arr = obj as? [String] { return arr }
        if let arr = obj as? [Any] { return arr.map { "\($0)" } }
        return []
    }

    func prettyJSON(_ name: String, args: [Any] = []) -> String {
        guard let obj = callJSON(name, args: args) else { return "null" }
        if JSONSerialization.isValidJSONObject(obj),
           let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\(obj)"
    }

    // MARK: - Event Handling

    func handleExternalCall(name: String, args: [Any]) {
        switch name {
        case "onProgress", "progress":
            if let pct = args.first as? Int ?? (args.first as? Double).map(Int.init) {
                lastProgress = pct
            }
        case "onLoaded", "loaded":
            isGameLoaded = true
        case "onConnection":
            let status = args.first.map { "\($0)" } ?? ""
            connectionStatus = status
            onConnectionEvent?(status)
        case "packetFromClient":
            if let pkt = args.first.map({ "\($0)" }) {
                onPacketFromClient?(pkt)
            }
        case "packetFromServer":
            if let pkt = args.first.map({ "\($0)" }) {
                onPacketFromServer?(pkt)
            }
        case "onExtensionResponse":
            if let payload = args.first.map({ "\($0)" }) {
                onExtensionResponse?(payload)
            }
        default:
            break
        }
    }

    // MARK: - Auth

    func isLoggedIn() -> Bool { callBool("auth.isLoggedIn") }
    func getServers() -> [[String: Any]] {
        (callJSON("auth.getServers") as? [[String: Any]]) ?? []
    }
    @discardableResult func login(username: String, password: String) -> Bool {
        callBool("auth.login", args: [username, password])
    }
    @discardableResult func connectTo(server: String) -> Any? {
        callJSON("auth.connectTo", args: [server])
    }
    func logout() { call("auth.logout") }

    // MARK: - Bank

    @discardableResult func openBank() -> Bool { callBool("bank.open") }
    func isBankOpen() -> Bool { callBool("bank.isOpen") }
    func isBankLoaded() -> Bool { callBool("bank.isLoaded") }
    func loadBankItems() { call("bank.loadItems") }
    func getBankItemsJSON() -> String { prettyJSON("bank.getItems") }
    @discardableResult func depositToBank(_ item: String) -> Bool { callBool("bank.deposit", args: [item]) }
    @discardableResult func withdrawFromBank(_ item: String) -> Bool { callBool("bank.withdraw", args: [item]) }

    // MARK: - Player & World

    func isPlayerLoaded() -> Bool { callBool("player.isLoaded") }
    func getPlayerCell() -> String { callString("player.getCell") }
    func getPlayerPad() -> String { callString("player.getPad") }
    func getPlayerMap() -> String { callString("player.getMap") }
    func getPlayerHp() -> Int { callInt("player.getHp") }
    func getPlayerMaxHp() -> Int { callInt("player.getMaxHp") }
    func getPlayerMp() -> Int { callInt("player.getMp") }
    func getPlayerMaxMp() -> Int { callInt("player.getMaxMp") }
    func getPlayerDataJSON() -> String { prettyJSON("player.getData") }
    func hasActiveBoost(_ boostType: String) -> Bool { callBool("player.hasActiveBoost", args: [boostType]) }

    @discardableResult func jump(cell: String, pad: String = "Spawn") -> Bool {
        callBool("player.jump", args: [cell, pad])
    }
    @discardableResult func joinMap(_ map: String, cell: String = "Enter", pad: String = "Spawn") -> Bool {
        callBool("player.joinMap", args: [map, cell, pad])
    }
    @discardableResult func rest() -> Bool { callBool("player.rest") }
    func goToPlayer(_ name: String) { call("player.goToPlayer", args: [name]) }

    func getCells() -> [String] { callStringArray("world.getCells") }
    func getCellPads() -> [String] { callStringArray("world.getCellPads") }
    func reloadMap() { call("world.reload") }
    func setSpawnPoint() { call("world.setSpawnPoint") }
    func loadMapSwf(_ swf: String) { call("world.loadSwf", args: [swf]) }

    // MARK: - Combat

    @discardableResult func attackMonster(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selector: [String: Any] = Int(trimmed).map { ["monsterMapId": $0] } ?? ["name": trimmed.isEmpty ? "*" : trimmed]
        return callBool("combat.attackMonster", args: [selector])
    }
    func cancelAutoAttack() { call("combat.cancelAutoAttack") }
    func cancelTarget() { call("combat.cancelTarget") }
    func hasTarget() -> Bool { callBool("combat.hasTarget") }
    func getTargetJSON() -> Any? { callJSON("combat.getTarget") }
    func getSkillCooldownRemaining(_ slot: Int) -> Int {
        callInt("combat.getSkillCooldownRemaining", args: [slot])
    }
    @discardableResult func useSkill(_ slot: Int, target: String? = nil, force: Bool = false) -> Bool {
        if let target = target {
            let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
            let selector: [String: Any] = Int(trimmed).map { ["monsterMapId": $0] } ?? ["name": trimmed.isEmpty ? "*" : trimmed]
            return callBool("combat.useSkill", args: [String(slot), selector, force])
        }
        return callBool("combat.useSkill", args: [String(slot)])
    }

    // MARK: - Drops, Inventory, House, TempInventory

    @discardableResult func acceptDrop(itemId: Int) -> Bool { callBool("drops.accept", args: [itemId]) }
    @discardableResult func rejectDrop(itemId: Int) -> Bool { callBool("drops.reject", args: [itemId]) }
    @discardableResult func acceptDrop(_ query: String) -> Bool {
        guard let id = Int(query.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return acceptDrop(itemId: id)
    }
    @discardableResult func rejectDrop(_ query: String) -> Bool {
        guard let id = Int(query.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return rejectDrop(itemId: id)
    }
    func getInventoryJSON() -> String { prettyJSON("inventory.getItems") }
    func getHouseJSON() -> String { prettyJSON("house.getItems") }
    func getTempInventoryJSON() -> String { prettyJSON("tempInventory.getItems") }
    @discardableResult func useInventoryItem(_ query: String) -> Bool { callBool("inventory.use", args: [query]) }
    @discardableResult func equipInventoryItem(_ query: String) -> Bool { callBool("inventory.equip", args: [query]) }

    // MARK: - Quests & Shops

    func loadQuest(_ id: Int, silent: Bool = false) { call("quests.load", args: [id, silent]) }
    @discardableResult func acceptQuest(_ id: Int) -> Bool { callBool("quests.accept", args: [id]) }
    func canCompleteQuest(_ id: Int) -> Bool { callBool("quests.canComplete", args: [id]) }
    @discardableResult func completeQuest(_ id: Int, rewardId: Int = -1) -> Bool {
        if rewardId > 0 {
            return callBool("quests.complete", args: [id, rewardId])
        }
        return callBool("quests.complete", args: [id])
    }
    func getAcceptedQuestsJSON() -> String { prettyJSON("quests.getAccepted") }

    func loadShop(_ id: Int) { call("shops.load", args: [id]) }
    func loadHairShop(_ id: Int) { call("shops.loadHairShop", args: [id]) }
    func loadArmorCustomize() { call("shops.loadArmorCustomize") }
    func closeShop() { call("shops.close") }

    // MARK: - Settings

    func setInfiniteRange(_ enabled: Bool) { call("settings.infiniteRange", args: [enabled]) }
    func setProvokeCell(_ enabled: Bool) { call("settings.provokeCell", args: [enabled]) }
    func setEnemyMagnet(_ enabled: Bool) { call("settings.enemyMagnet", args: [enabled]) }
    func setOtherPlayersVisible(_ visible: Bool) { call("settings.setOtherPlayersVisible", args: [visible]) }
    func setSkipCutscenes(_ enabled: Bool) { call("settings.skipCutscenes", args: [enabled]) }
    func setAnimationsEnabled(_ enabled: Bool) { call("settings.setAnimationsEnabled", args: [enabled]) }
    func setCollisionsEnabled(_ enabled: Bool) { call("settings.setCollisionsEnabled", args: [enabled]) }
    func setDeathAdsVisible(_ visible: Bool) { call("settings.setDeathAdsVisible", args: [visible]) }
    func setLagKillerEnabled(_ enabled: Bool) { call("settings.setLagKillerEnabled", args: [enabled]) }
    func setWalkSpeed(_ speed: Int) { call("settings.setWalkSpeed", args: [speed]) }
    func setFrameRate(_ fps: Int) { call("settings.setFrameRate", args: [fps]) }
    func setCustomName(_ name: String) { call("settings.setCustomName", args: [name]) }
    func resetCustomName() { call("settings.resetCustomName") }
    func setCustomGuild(_ guild: String) { call("settings.setCustomGuild", args: [guild]) }
    func resetCustomGuild() { call("settings.resetCustomGuild") }

    // MARK: - Packets

    @discardableResult func sendClientPacket(_ packet: String, encoding: String = "string") -> Bool {
        callBool("flash.sendClientPacket", args: [packet, encoding])
    }

    @discardableResult func sendServerPacket(_ packet: String) -> Any? {
        call("flash.callGameFunction", args: ["sfc.sendXtMessage", "zm", packet])
    }
}

