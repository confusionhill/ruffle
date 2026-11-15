import Foundation
import Combine

enum SkillConditionMetric: String, Codable, CaseIterable, Identifiable {
    case playerHpBelow = "HP % ≤"
    case playerHpAbove = "HP % ≥"
    case playerMpBelow = "MP % ≤"
    case playerMpAbove = "MP % ≥"
    case always = "Always (Priority)"

    var id: String { rawValue }
}

struct SkillRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var slot: Int
    var metric: SkillConditionMetric
    var threshold: Int
    var enabled: Bool = true

    func matches(hp: Int, maxHp: Int, mp: Int, maxMp: Int) -> Bool {
        guard enabled else { return false }
        let safeMaxHp = max(1, maxHp)
        let safeMaxMp = max(1, maxMp)
        let hpPct = (hp * 100) / safeMaxHp
        let mpPct = (mp * 100) / safeMaxMp

        switch metric {
        case .playerHpBelow:
            return threshold == 0 ? (hp == 0) : (hpPct <= threshold)
        case .playerHpAbove:
            return hpPct >= threshold
        case .playerMpBelow:
            return threshold == 0 ? (mp == 0) : (mpPct <= threshold)
        case .playerMpAbove:
            return mpPct >= threshold
        case .always:
            return true
        }
    }
}

struct CombatProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var skills: [Int]
    var skillDelayMs: Int
    var targetQuery: String
    var antiCounter: Bool
    var skillRules: [SkillRule] = []

    static let defaultProfiles: [CombatProfile] = [
        CombatProfile(
            name: "Balanced Rotation (1-4)",
            skills: [1, 2, 3, 4],
            skillDelayMs: 350,
            targetQuery: "*",
            antiCounter: true,
            skillRules: [
                SkillRule(slot: 3, metric: .playerHpBelow, threshold: 45, enabled: true)
            ]
        ),
        CombatProfile(
            name: "Full Spam (1-5)",
            skills: [1, 2, 3, 4, 5],
            skillDelayMs: 250,
            targetQuery: "*",
            antiCounter: false,
            skillRules: [
                SkillRule(slot: 3, metric: .playerHpBelow, threshold: 30, enabled: true)
            ]
        )
    ]
}

@MainActor
final class CombatEngine: ObservableObject {
    private static let profilesStorageKey = "lucent.combat.profiles.v2"

    private let bridge: LucentBridge
    private var timer: Timer?
    private var skillCursor = 0

    @Published var profiles: [CombatProfile] {
        didSet { saveProfiles() }
    }
    @Published var selectedProfileId: UUID
    @Published var isAutoAttacking = false
    @Published var statusText = "Idle"

    init(bridge: LucentBridge) {
        self.bridge = bridge
        let loaded = Self.loadProfiles() ?? CombatProfile.defaultProfiles
        let initial = loaded.isEmpty ? CombatProfile.defaultProfiles : loaded
        self.profiles = initial
        self.selectedProfileId = initial[0].id
    }

    var activeProfile: CombatProfile {
        profiles.first(where: { $0.id == selectedProfileId }) ?? profiles[0]
    }

    func createProfile() {
        let created = CombatProfile(
            name: "Custom Profile",
            skills: [1, 2, 3, 4],
            skillDelayMs: 350,
            targetQuery: "*",
            antiCounter: true,
            skillRules: [
                SkillRule(slot: 3, metric: .playerHpBelow, threshold: 45, enabled: true)
            ]
        )
        profiles.append(created)
        selectedProfileId = created.id
    }

    func deleteSelectedProfile() {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == selectedProfileId }
        if !profiles.contains(where: { $0.id == selectedProfileId }), let first = profiles.first {
            selectedProfileId = first.id
        }
    }

    func toggleAutoAttack() {
        if isAutoAttacking {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isAutoAttacking else { return }
        isAutoAttacking = true
        skillCursor = 0
        statusText = "Running (\(activeProfile.name))"

        let interval = max(0.15, Double(activeProfile.skillDelayMs) / 1000.0)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isAutoAttacking = false
        statusText = "Idle"
        bridge.cancelAutoAttack()
    }

    private func tick() {
        guard bridge.isPlayerLoaded() else { return }
        let profile = activeProfile

        if !bridge.hasTarget() {
            let target = profile.targetQuery.isEmpty ? "*" : profile.targetQuery
            if !bridge.attackMonster(target) {
                statusText = "Waiting for \(target)..."
                return
            }
            statusText = "Targeting \(target)"
        }

        let hp = bridge.getPlayerHp()
        let maxHp = max(1, bridge.getPlayerMaxHp())
        let mp = bridge.getPlayerMp()
        let maxMp = max(1, bridge.getPlayerMaxMp())

        // 1. Evaluate conditional skill rules in priority order
        for rule in profile.skillRules {
            if rule.matches(hp: hp, maxHp: maxHp, mp: mp, maxMp: maxMp),
               bridge.getSkillCooldownRemaining(rule.slot) == 0 {
                _ = bridge.useSkill(rule.slot)
                statusText = "Rule: skill \(rule.slot) (\(rule.metric.rawValue) \(rule.threshold)%)"
                return
            }
        }

        // 2. Fallback to main rotation
        guard !profile.skills.isEmpty else { return }
        for offset in 0..<profile.skills.count {
            let idx = (skillCursor + offset) % profile.skills.count
            let slot = profile.skills[idx]
            if bridge.getSkillCooldownRemaining(slot) == 0 {
                _ = bridge.useSkill(slot)
                skillCursor = (idx + 1) % profile.skills.count
                statusText = "Used skill \(slot)"
                return
            }
        }
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.profilesStorageKey)
    }

    private static func loadProfiles() -> [CombatProfile]? {
        guard let data = UserDefaults.standard.data(forKey: profilesStorageKey) else { return nil }
        return try? JSONDecoder().decode([CombatProfile].self, from: data)
    }
}
