-- Lucent Lua SDK Prelude (Coroutine Helpers)

function waitUntil(predicate, timeoutMs, pollMs)
    local timeout = timeoutMs or 10000
    local poll = pollMs or 150
    local elapsed = 0
    while not predicate() do
        if elapsed >= timeout then
            return false
        end
        sleep(poll)
        elapsed = elapsed + poll
    end
    return true
end

function safeJoin(mapName, cell, pad)
    cell = cell or "Enter"
    pad = pad or "Spawn"
    local baseMap = string.lower(string.match(mapName, "^([^%-]+)") or mapName)
    if string.lower(player.map() or "") == baseMap then
        player.jump(cell, pad)
        sleep(250)
        return true
    end
    player.join(mapName, cell, pad)
    return waitUntil(function()
        return player.isLoaded() and string.lower(player.map() or "") == baseMap
    end, 15000, 250)
end

function kill(targetQuery, skills)
    local target = targetQuery or "*"
    local rotation = skills or { 1, 2, 3, 4 }

    if not combat.hasTarget() then
        if not combat.attack(target) then
            sleep(250)
            return false
        end
    end

    local idx = 1
    while combat.hasTarget() do
        local slot = rotation[idx]
        if combat.cooldown(slot) == 0 then
            combat.useSkill(slot)
        end
        idx = (idx % #rotation) + 1
        sleep(250)
    end
    return true
end

function killForItem(targetQuery, itemName, quantity, skills)
    local qty = quantity or 1
    env.whitelistDrop(itemName)
    env.enableDrops(true)

    while (inventory.count(itemName) + temp.count(itemName)) < qty do
        if player.isLoaded() then
            kill(targetQuery, skills)
        else
            sleep(250)
        end
        sleep(100)
    end
    return true
end

local function matchesSkillRule(rule)
    if rule.enabled == false then return false end
    if type(rule.cond) == "function" then
        return rule.cond()
    end

    local when = rule.when or "always"
    local val = rule.value or 0
    local hp = player.hp()
    local maxHp = math.max(1, player.maxHp())
    local mp = player.mp()
    local maxMp = math.max(1, player.maxMp())
    local hpPct = (hp * 100) / maxHp
    local mpPct = (mp * 100) / maxMp

    if when == "hp<=" then
        return val == 0 and (hp == 0) or (hpPct <= val)
    elseif when == "hp>=" then
        return hpPct >= val
    elseif when == "mp<=" then
        return val == 0 and (mp == 0) or (mpPct <= val)
    elseif when == "mp>=" then
        return mpPct >= val
    elseif when == "always" then
        return true
    end
    return false
end

function castWithRules(skills, rules, skillCursor)
    local cursor = skillCursor or 1
    if rules then
        for _, rule in ipairs(rules) do
            if matchesSkillRule(rule) and combat.cooldown(rule.slot) == 0 then
                combat.useSkill(rule.slot)
                return cursor
            end
        end
    end

    if skills and #skills > 0 then
        for offset = 0, #skills - 1 do
            local idx = ((cursor - 1 + offset) % #skills) + 1
            local slot = skills[idx]
            if combat.cooldown(slot) == 0 then
                combat.useSkill(slot)
                return (idx % #skills) + 1
            end
        end
    end

    return cursor
end
