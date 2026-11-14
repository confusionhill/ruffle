import Foundation
import LuaKit

@MainActor
final class LuaLucentSDK {
    let engine: LuaEngine
    private let bridge: LucentBridge
    private let envManager: EnvironmentManager
    private let combatEngine: CombatEngine

    init(
        engine: LuaEngine,
        bridge: LucentBridge,
        envManager: EnvironmentManager,
        combatEngine: CombatEngine
    ) {
        self.engine = engine
        self.bridge = bridge
        self.envManager = envManager
        self.combatEngine = combatEngine
        registerAll()
        loadBundledPrelude()
    }

    func resetAndReload() {
        engine.resetState()
        registerAll()
        loadBundledPrelude()
    }

    private func loadBundledPrelude() {
        guard let url = Bundle.main.url(forResource: "prelude", withExtension: "lua"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        engine.loadPrelude(src, name: "prelude.lua")
    }

    private func registerAll() {
        registerPlayer()
        registerWorld()
        registerCombat()
        registerInventoryAndBank()
        registerQuestsDropsShops()
        registerEnv()
        registerPacketAndSettings()
    }

    // MARK: - player.*

    private func registerPlayer() {
        engine.registerFunction(table: "player", name: "isLoaded") { [weak self] _ in
            .bool(self?.bridge.isPlayerLoaded() ?? false)
        }
        engine.registerFunction(table: "player", name: "hp") { [weak self] _ in
            .int(self?.bridge.getPlayerHp() ?? 0)
        }
        engine.registerFunction(table: "player", name: "maxHp") { [weak self] _ in
            .int(self?.bridge.getPlayerMaxHp() ?? 0)
        }
        engine.registerFunction(table: "player", name: "mp") { [weak self] _ in
            .int(self?.bridge.getPlayerMp() ?? 0)
        }
        engine.registerFunction(table: "player", name: "maxMp") { [weak self] _ in
            .int(self?.bridge.getPlayerMaxMp() ?? 0)
        }
        engine.registerFunction(table: "player", name: "cell") { [weak self] _ in
            .string(self?.bridge.getPlayerCell() ?? "")
        }
        engine.registerFunction(table: "player", name: "pad") { [weak self] _ in
            .string(self?.bridge.getPlayerPad() ?? "")
        }
        engine.registerFunction(table: "player", name: "map") { [weak self] _ in
            .string(self?.bridge.getPlayerMap() ?? "")
        }
        engine.registerFunction(table: "player", name: "data") { [weak self] _ in
            LuaValue.from(any: self?.bridge.callJSON("player.getData"))
        }
        engine.registerFunction(table: "player", name: "jump") { [weak self] args in
            let cell = args.first?.stringValue ?? "Enter"
            let pad = args.dropFirst().first?.stringValue ?? "Spawn"
            return .bool(self?.bridge.jump(cell: cell, pad: pad) ?? false)
        }
        engine.registerFunction(table: "player", name: "join") { [weak self] args in
            guard let map = args.first?.stringValue else { return .bool(false) }
            let cell = args.dropFirst().first?.stringValue ?? "Enter"
            let pad = args.dropFirst(2).first?.stringValue ?? "Spawn"
            return .bool(self?.bridge.joinMap(map, cell: cell, pad: pad) ?? false)
        }
        engine.registerFunction(table: "player", name: "rest") { [weak self] _ in
            .bool(self?.bridge.rest() ?? false)
        }
        engine.registerFunction(table: "player", name: "goTo") { [weak self] args in
            if let name = args.first?.stringValue {
                self?.bridge.goToPlayer(name)
            }
            return .nil
        }
        engine.registerFunction(table: "player", name: "hasBoost") { [weak self] args in
            guard let kind = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.hasActiveBoost(kind) ?? false)
        }
    }

    // MARK: - world.*

    private func registerWorld() {
        engine.registerFunction(table: "world", name: "cells") { [weak self] _ in
            .array((self?.bridge.getCells() ?? []).map { .string($0) })
        }
        engine.registerFunction(table: "world", name: "pads") { [weak self] _ in
            .array((self?.bridge.getCellPads() ?? []).map { .string($0) })
        }
        engine.registerFunction(table: "world", name: "reload") { [weak self] _ in
            self?.bridge.reloadMap()
            return .nil
        }
        engine.registerFunction(table: "world", name: "setSpawnPoint") { [weak self] _ in
            self?.bridge.setSpawnPoint()
            return .nil
        }
        engine.registerFunction(table: "world", name: "loadSwf") { [weak self] args in
            if let path = args.first?.stringValue {
                self?.bridge.loadMapSwf(path)
            }
            return .nil
        }
    }

    // MARK: - combat.*

    private func registerCombat() {
        engine.registerFunction(table: "combat", name: "attack") { [weak self] args in
            let target = args.first?.stringValue ?? "*"
            return .bool(self?.bridge.attackMonster(target) ?? false)
        }
        engine.registerFunction(table: "combat", name: "useSkill") { [weak self] args in
            guard let slot = args.first?.intValue else { return .bool(false) }
            let target = args.dropFirst().first?.stringValue
            let force = args.dropFirst(2).first?.boolValue ?? false
            return .bool(self?.bridge.useSkill(slot, target: target, force: force) ?? false)
        }
        engine.registerFunction(table: "combat", name: "hasTarget") { [weak self] _ in
            .bool(self?.bridge.hasTarget() ?? false)
        }
        engine.registerFunction(table: "combat", name: "target") { [weak self] _ in
            LuaValue.from(any: self?.bridge.getTargetJSON())
        }
        engine.registerFunction(table: "combat", name: "cooldown") { [weak self] args in
            guard let slot = args.first?.intValue else { return .int(0) }
            return .int(self?.bridge.getSkillCooldownRemaining(slot) ?? 0)
        }
        engine.registerFunction(table: "combat", name: "cancelAutoAttack") { [weak self] _ in
            self?.bridge.cancelAutoAttack()
            return .nil
        }
        engine.registerFunction(table: "combat", name: "cancelTarget") { [weak self] _ in
            self?.bridge.cancelTarget()
            return .nil
        }
        engine.registerFunction(table: "combat", name: "startAuto") { [weak self] args in
            guard let engine = self?.combatEngine else { return .nil }
            if let profileName = args.first?.stringValue,
               let match = engine.profiles.first(where: { $0.name.caseInsensitiveCompare(profileName) == .orderedSame }) {
                engine.selectedProfileId = match.id
            }
            engine.start()
            return .nil
        }
        engine.registerFunction(table: "combat", name: "stopAuto") { [weak self] _ in
            self?.combatEngine.stop()
            return .nil
        }
    }

    // MARK: - inventory.*, temp.*, bank.*, house.*

    private func registerInventoryAndBank() {
        engine.registerFunction(table: "inventory", name: "items") { [weak self] _ in
            LuaValue.from(any: self?.bridge.callJSON("inventory.getItems"))
        }
        engine.registerFunction(table: "inventory", name: "count") { [weak self] args in
            guard let name = args.first?.stringValue else { return .int(0) }
            return .int(self?.countItem(in: "inventory.getItems", name: name) ?? 0)
        }
        engine.registerFunction(table: "inventory", name: "equip") { [weak self] args in
            guard let name = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.equipInventoryItem(name) ?? false)
        }
        engine.registerFunction(table: "inventory", name: "use") { [weak self] args in
            guard let name = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.useInventoryItem(name) ?? false)
        }

        engine.registerFunction(table: "temp", name: "items") { [weak self] _ in
            LuaValue.from(any: self?.bridge.callJSON("tempInventory.getItems"))
        }
        engine.registerFunction(table: "temp", name: "count") { [weak self] args in
            guard let name = args.first?.stringValue else { return .int(0) }
            return .int(self?.countItem(in: "tempInventory.getItems", name: name) ?? 0)
        }

        engine.registerFunction(table: "house", name: "items") { [weak self] _ in
            LuaValue.from(any: self?.bridge.callJSON("house.getItems"))
        }

        engine.registerFunction(table: "bank", name: "open") { [weak self] _ in
            .bool(self?.bridge.openBank() ?? false)
        }
        engine.registerFunction(table: "bank", name: "isOpen") { [weak self] _ in
            .bool(self?.bridge.isBankOpen() ?? false)
        }
        engine.registerFunction(table: "bank", name: "items") { [weak self] _ in
            LuaValue.from(any: self?.bridge.callJSON("bank.getItems"))
        }
        engine.registerFunction(table: "bank", name: "deposit") { [weak self] args in
            guard let item = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.depositToBank(item) ?? false)
        }
        engine.registerFunction(table: "bank", name: "withdraw") { [weak self] args in
            guard let item = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.withdrawFromBank(item) ?? false)
        }
    }

    private func countItem(in endpoint: String, name: String) -> Int {
        guard let arr = bridge.callJSON(endpoint) as? [[String: Any]] else { return 0 }
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var total = 0
        for item in arr {
            let itemName = (item["sName"] as? String) ?? (item["name"] as? String) ?? ""
            if itemName.caseInsensitiveCompare(target) == .orderedSame {
                let qty = (item["iQty"] as? Int) ?? (item["quantity"] as? Int) ?? 1
                total += qty
            }
        }
        return total
    }

    // MARK: - quests.*, drops.*, shops.*

    private func registerQuestsDropsShops() {
        engine.registerFunction(table: "quests", name: "load") { [weak self] args in
            if let id = args.first?.intValue {
                let silent = args.dropFirst().first?.boolValue ?? false
                self?.bridge.loadQuest(id, silent: silent)
            }
            return .nil
        }
        engine.registerFunction(table: "quests", name: "accept") { [weak self] args in
            guard let id = args.first?.intValue else { return .bool(false) }
            return .bool(self?.bridge.acceptQuest(id) ?? false)
        }
        engine.registerFunction(table: "quests", name: "canComplete") { [weak self] args in
            guard let id = args.first?.intValue else { return .bool(false) }
            return .bool(self?.bridge.canCompleteQuest(id) ?? false)
        }
        engine.registerFunction(table: "quests", name: "complete") { [weak self] args in
            guard let id = args.first?.intValue else { return .bool(false) }
            let reward = args.dropFirst().first?.intValue ?? -1
            return .bool(self?.bridge.completeQuest(id, rewardId: reward) ?? false)
        }
        engine.registerFunction(table: "quests", name: "accepted") { [weak self] _ in
            LuaValue.from(any: self?.bridge.callJSON("quests.getAccepted"))
        }

        engine.registerFunction(table: "drops", name: "accept") { [weak self] args in
            guard let name = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.acceptDrop(name) ?? false)
        }
        engine.registerFunction(table: "drops", name: "reject") { [weak self] args in
            guard let name = args.first?.stringValue else { return .bool(false) }
            return .bool(self?.bridge.rejectDrop(name) ?? false)
        }

        engine.registerFunction(table: "shops", name: "load") { [weak self] args in
            if let id = args.first?.intValue { self?.bridge.loadShop(id) }
            return .nil
        }
        engine.registerFunction(table: "shops", name: "loadHair") { [weak self] args in
            if let id = args.first?.intValue { self?.bridge.loadHairShop(id) }
            return .nil
        }
        engine.registerFunction(table: "shops", name: "loadArmorCustomize") { [weak self] _ in
            self?.bridge.loadArmorCustomize()
            return .nil
        }
        engine.registerFunction(table: "shops", name: "close") { [weak self] _ in
            self?.bridge.closeShop()
            return .nil
        }
    }

    // MARK: - env.*

    private func registerEnv() {
        engine.registerFunction(table: "env", name: "enableDrops") { [weak self] args in
            self?.envManager.dropsEnabled = args.first?.boolValue ?? true
            return .nil
        }
        engine.registerFunction(table: "env", name: "rejectUnregistered") { [weak self] args in
            self?.envManager.rejectUnregisteredDrops = args.first?.boolValue ?? true
            return .nil
        }
        engine.registerFunction(table: "env", name: "whitelistDrop") { [weak self] args in
            if let item = args.first?.stringValue {
                self?.envManager.addDropItem(item)
            }
            return .nil
        }
        engine.registerFunction(table: "env", name: "enableQuests") { [weak self] args in
            self?.envManager.questsEnabled = args.first?.boolValue ?? true
            return .nil
        }
        engine.registerFunction(table: "env", name: "registerQuest") { [weak self] args in
            if let qid = args.first?.intValue {
                let reward = args.dropFirst().first?.intValue
                self?.envManager.addQuest(id: qid, rewardId: reward)
            }
            return .nil
        }
        engine.registerFunction(table: "env", name: "enableBoosts") { [weak self] args in
            self?.envManager.boostsEnabled = args.first?.boolValue ?? true
            return .nil
        }
        engine.registerFunction(table: "env", name: "registerBoost") { [weak self] args in
            if let name = args.first?.stringValue {
                self?.envManager.addBoost(name)
            }
            return .nil
        }
    }

    // MARK: - packet.* & settings.*

    private func registerPacketAndSettings() {
        engine.registerFunction(table: "packet", name: "send") { [weak self] args in
            if let pkt = args.first?.stringValue {
                self?.bridge.sendServerPacket(pkt)
            }
            return .nil
        }
        engine.registerFunction(table: "packet", name: "sendClient") { [weak self] args in
            guard let pkt = args.first?.stringValue else { return .bool(false) }
            let enc = args.dropFirst().first?.stringValue ?? "string"
            return .bool(self?.bridge.sendClientPacket(pkt, encoding: enc) ?? false)
        }

        engine.registerFunction(table: "settings", name: "infiniteRange") { [weak self] args in
            self?.bridge.setInfiniteRange(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "provokeCell") { [weak self] args in
            self?.bridge.setProvokeCell(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "enemyMagnet") { [weak self] args in
            self?.bridge.setEnemyMagnet(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "hidePlayers") { [weak self] args in
            let hide = args.first?.boolValue ?? true
            self?.bridge.setOtherPlayersVisible(!hide)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "skipCutscenes") { [weak self] args in
            self?.bridge.setSkipCutscenes(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "animations") { [weak self] args in
            self?.bridge.setAnimationsEnabled(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "collisions") { [weak self] args in
            self?.bridge.setCollisionsEnabled(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "deathAds") { [weak self] args in
            self?.bridge.setDeathAdsVisible(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "lagKiller") { [weak self] args in
            self?.bridge.setLagKillerEnabled(args.first?.boolValue ?? true)
            return .nil
        }
        engine.registerFunction(table: "settings", name: "walkSpeed") { [weak self] args in
            if let speed = args.first?.intValue { self?.bridge.setWalkSpeed(speed) }
            return .nil
        }
        engine.registerFunction(table: "settings", name: "fps") { [weak self] args in
            if let fps = args.first?.intValue { self?.bridge.setFrameRate(fps) }
            return .nil
        }
        engine.registerFunction(table: "settings", name: "customName") { [weak self] args in
            if let s = args.first?.stringValue, !s.isEmpty {
                self?.bridge.setCustomName(s)
            } else {
                self?.bridge.resetCustomName()
            }
            return .nil
        }
        engine.registerFunction(table: "settings", name: "customGuild") { [weak self] args in
            if let s = args.first?.stringValue, !s.isEmpty {
                self?.bridge.setCustomGuild(s)
            } else {
                self?.bridge.resetCustomGuild()
            }
            return .nil
        }
    }
}
