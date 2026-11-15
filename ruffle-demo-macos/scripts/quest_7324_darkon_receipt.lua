-- ============================================================================
-- Quest 7324: Darkon's First Errand (Banana -> Darkon's Receipt)
-- Map: arcangrove (private room), Cell: leftBackA, Pad: Right
-- ============================================================================

-- >>> CONFIGURE YOUR CLASS SKILLS HERE <<<
local SKILLS = { 1, 2, 3, 4 }      -- e.g. { 1, 2, 3, 4 } or { 2, 1, 3, 5 }
local SKILL_DELAY_MS = 250          -- delay between skill checks
local HEAL_SLOT = 3                 -- set to nil if your class has no heal skill
local HEAL_HP_PERCENT = 45          -- cast HEAL_SLOT when HP% <= this value

-- >>> FARM SETTINGS <<<
local QUEST_ID = 7324
local MAP_NAME = "arcangrove-99999" -- private room
local TARGET_CELL = "leftBackA"
local TARGET_PAD = "Right"
local TARGET_RECEIPTS = 222         -- set to 0 to farm indefinitely

-- ============================================================================
-- Helpers
-- ============================================================================

local function resolveCell(desired)
    local lowerDesired = string.lower(desired)
    for _, cell in ipairs(world.cells()) do
        if string.lower(cell) == lowerDesired then
            return cell
        end
    end
    return desired
end

local function ensureLocation()
    local baseMap = string.lower(string.match(MAP_NAME, "^([^%-]+)") or MAP_NAME)
    if string.lower(player.map() or "") ~= baseMap then
        print("Joining " .. MAP_NAME .. "...")
        safeJoin(MAP_NAME, TARGET_CELL, TARGET_PAD)
        sleep(500)
    end

    local actualCell = resolveCell(TARGET_CELL)
    if string.lower(player.cell() or "") ~= string.lower(actualCell) then
        print("Jumping to " .. actualCell .. " (" .. TARGET_PAD .. ")...")
        player.jump(actualCell, TARGET_PAD)
        sleep(400)
    end
end

local function tryTurnIn()
    if not quests.canComplete(QUEST_ID) then
        return false
    end

    print("Quest " .. QUEST_ID .. " ready! Turning in...")
    combat.cancelAutoAttack()
    combat.cancelTarget()
    sleep(300)

    quests.complete(QUEST_ID)
    sleep(400)
    drops.accept("Darkon's Receipt")
    sleep(250)
    quests.accept(QUEST_ID)
    sleep(250)

    print("Darkon's Receipt count:", inventory.count("Darkon's Receipt"))
    return true
end

local function fightOneCycle(skillCursor)
    if not combat.hasTarget() then
        if not combat.attack("*") then
            sleep(300)
            return skillCursor
        end
    end

    local maxHp = math.max(1, player.maxHp())
    local hpPct = (player.hp() * 100) / maxHp

    if HEAL_SLOT and hpPct <= HEAL_HP_PERCENT and combat.cooldown(HEAL_SLOT) == 0 then
        combat.useSkill(HEAL_SLOT)
        return skillCursor
    end

    if #SKILLS > 0 then
        for offset = 0, #SKILLS - 1 do
            local idx = ((skillCursor - 1 + offset) % #SKILLS) + 1
            local slot = SKILLS[idx]
            if combat.cooldown(slot) == 0 then
                combat.useSkill(slot)
                return (idx % #SKILLS) + 1
            end
        end
    end

    return skillCursor
end

-- ============================================================================
-- Main Entry
-- ============================================================================

print("Starting Quest 7324 (Darkon's Receipt) bot...")

settings.infiniteRange(true)
settings.enemyMagnet(true)

env.whitelistDrop("Banana")
env.whitelistDrop("Darkon's Receipt")
env.enableDrops(true)

ensureLocation()

quests.load(QUEST_ID, true)
sleep(400)
quests.accept(QUEST_ID)
sleep(250)

local skillCursor = 1

while true do
    if TARGET_RECEIPTS > 0 and inventory.count("Darkon's Receipt") >= TARGET_RECEIPTS then
        print("Target reached:", inventory.count("Darkon's Receipt"), "Darkon's Receipt!")
        combat.cancelAutoAttack()
        combat.cancelTarget()
        break
    end

    if player.isLoaded() then
        ensureLocation()

        if not tryTurnIn() then
            -- Re-accept periodically in case quest was not active
            quests.accept(QUEST_ID)
            skillCursor = fightOneCycle(skillCursor)
        end
    end

    sleep(SKILL_DELAY_MS)
end

print("Bot finished.")
