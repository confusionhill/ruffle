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
