-- ============================================================================
-- Quest 7324: Darkon's First Errand (Banana -> Darkon's Receipt)
-- Map: arcangrove (private room), Cell: leftBackA, Pad: Right
-- ============================================================================

-- >>> CONFIGURE YOUR CLASS SKILLS & CONDITIONAL RULES HERE <<<
local SKILLS = { 1, 2, 3, 4 }      -- main rotation, e.g. { 1, 2, 3, 4 }
local SKILL_DELAY_MS = 250          -- delay between skill checks
local SKILL_RULES = {
    -- Evaluated top-to-bottom before SKILLS rotation:
    -- when = "hp<=" | "hp>=" | "mp<=" | "mp>=" | "always" (value = 0 matches exact 0)
    -- Or use cond = function() return player.mp() == 0 end
    { slot = 3, when = "hp<=", value = 45, enabled = true },
    { slot = 5, when = "mp<=", value = 0,  enabled = false }, -- enable if your class uses a 0-MP / low-MP skill
}

-- >>> FARM SETTINGS <<<
local QUEST_ID = 7324
local MAP_NAME = "arcangrove-99999" -- private room
local TARGET_CELL = "leftBack"
local TARGET_PAD = "Right"
local TARGET_RECEIPTS = 22         -- set to 0 to farm indefinitely

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

    return castWithRules(SKILLS, SKILL_RULES, skillCursor)
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

