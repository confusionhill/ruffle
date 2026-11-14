import Foundation
import Combine

struct CombatProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var skills: [Int]
    var skillDelayMs: Int
    var healHpPercent: Int
    var targetQuery: String
    var antiCounter: Bool

    static let defaultProfiles: [CombatProfile] = [
        CombatProfile(
            name: "Balanced Rotation (1-4)",
            skills: [1, 2, 3, 4],
            skillDelayMs: 350,
            healHpPercent: 45,
            targetQuery: "*",
            antiCounter: true
        ),
        CombatProfile(
            name: "Full Spam (1-5)",
            skills: [1, 2, 3, 4, 5],
            skillDelayMs: 250,
            healHpPercent: 30,
            targetQuery: "*",
            antiCounter: false
        )
    ]
}

@MainActor
final class CombatEngine: ObservableObject {
    private let bridge: LucentBridge
    private var timer: Timer?
    private var skillCursor = 0

    @Published var profiles: [CombatProfile] = CombatProfile.defaultProfiles
    @Published var selectedProfileId: UUID
    @Published var isAutoAttacking = false
    @Published var statusText = "Idle"

    init(bridge: LucentBridge) {
        self.bridge = bridge
        self.selectedProfileId = CombatProfile.defaultProfiles[0].id
    }

    var activeProfile: CombatProfile {
        profiles.first(where: { $0.id == selectedProfileId }) ?? profiles[0]
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

        let hp = bridge.getPlayerHp()
        let maxHp = max(1, bridge.getPlayerMaxHp())
        let hpPct = (hp * 100) / maxHp

        if !bridge.hasTarget() {
            let target = profile.targetQuery.isEmpty ? "*" : profile.targetQuery
            _ = bridge.attackMonster(target)
            statusText = "Targeting \(target)..."
            return
        }

        if hpPct <= profile.healHpPercent && profile.skills.contains(3) {
            if bridge.getSkillCooldownRemaining(3) == 0 {
                _ = bridge.useSkill(3)
                return
            }
        }

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
}
