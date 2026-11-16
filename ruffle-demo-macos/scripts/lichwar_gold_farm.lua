-- ============================================================================
-- Lichwar Gold Farm (Quests 10282, 10283, 10284)
-- Map: lichwar, Cell: r9, Pad: Right
-- Targets: 3 Mega Grimskull War Medal, 5 Grimskull War Medal, 5 Noxus Giant Slain
-- ============================================================================

-- >>> CONFIGURE YOUR CLASS SKILLS & CONDITIONAL RULES HERE <<<
local SKILLS = { 1, 2, 3, 4 }      -- 0 = Auto Attack, 1-4 = class skills
local SKILL_DELAY_MS = 250          -- delay between skill checks
local SKILL_RULES = {
    -- Evaluated top-to-bottom before SKILLS rotation:
    -- when = "hp<=" | "hp>=" | "mp<=" | "mp>=" | "always" (value = 0 matches exact 0)
    -- Or use cond = function() return player.mp() == 0 end
    { slot = 3, when = "hp<=", value = 45, enabled = true },
    { slot = 4, when = "mp<=", value = 0,  enabled = false },
}

-- >>> FARM SETTINGS <<<
local QUEST_IDS = { 10282, 10283, 10284 }
local MAP_NAME = "lichwar"          -- change to "lichwar-99999" for a private room
local TARGET_CELL = "r9"
local TARGET_PAD = "Right"
local TARGET_TURNINS = 0            -- set > 0 to stop after N total quest turn-ins, 0 = infinite

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

local function loadAndAcceptAllQuests()
    for _, qid in ipairs(QUEST_IDS) do
        quests.load(qid, true)
    end
    sleep(400)
    for _, qid in ipairs(QUEST_IDS) do
        quests.accept(qid)
    end
end

local function tryTurnInAll()
    local turnedIn = 0
    for _, qid in ipairs(QUEST_IDS) do
        if quests.canComplete(qid) then
            if turnedIn == 0 then
                combat.cancelAutoAttack()
                combat.cancelTarget()
                sleep(250)
            end
            print("Turning in quest " .. qid .. "...")
            quests.complete(qid)
            sleep(300)
            quests.accept(qid)
            sleep(200)
            turnedIn = turnedIn + 1
        end
    end
    return turnedIn
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

print("Starting Lichwar Gold Farm (10282, 10283, 10284)...")

settings.infiniteRange(true)
settings.enemyMagnet(true)

env.whitelistDrop("Mega Grimskull War Medal")
env.whitelistDrop("Grimskull War Medal")
env.enableDrops(true)

ensureLocation()
loadAndAcceptAllQuests()

local skillCursor = 1
local totalTurnIns = 0

while true do
    if TARGET_TURNINS > 0 and totalTurnIns >= TARGET_TURNINS then
        print("Reached target turn-ins:", totalTurnIns)
        combat.cancelAutoAttack()
        combat.cancelTarget()
        break
    end

    if player.isLoaded() then
        ensureLocation()

        local completed = tryTurnInAll()
        if completed > 0 then
            totalTurnIns = totalTurnIns + completed
            print("Total quest turn-ins:", totalTurnIns)
        else
            for _, qid in ipairs(QUEST_IDS) do
                quests.accept(qid)
            end
            skillCursor = fightOneCycle(skillCursor)
        end
    end

    sleep(SKILL_DELAY_MS)
end

print("Bot finished.")
