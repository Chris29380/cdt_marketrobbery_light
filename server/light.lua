-- Périmètre de la version gratuite : les options absentes de l'éditeur
-- sont également neutralisées côté serveur, y compris dans les imports.
local D=require 'shared.domain'
local L={}
local baseline=D.copy(Config.defaults)
local basic={minPolice=true,cooldown=true,globalCooldown=true,maxDuration=true,abandonDelay=true,alertDelay=true,intimidateDuration=true,registerDuration=true,safeRequiresRegisters=true,registerReward=true,safeReward=true,safeLoot=true,safeMinigame=true}
local function game(value)
    if type(value)~='table' then return value end
    local difficulty=value.difficulty
    if not ({easy=true,normal=true,hard=true,expert=true})[difficulty] then difficulty='normal' end
    return {type='dial',difficulty=difficulty}
end
local function settings(value,defaults)
    if type(value)~='table' then return value end
    local result=defaults and D.copy(baseline) or {}
    for key,v in pairs(value) do if basic[key] then result[key]=D.copy(v) end end
    if result.safeMinigame then result.safeMinigame=game(result.safeMinigame) end
    return result
end
function L.config(value)
    if type(value)~='table' then return value end
    value=D.copy(value)
    value.defaults=settings(value.defaults,true)
    if type(value.stores)~='table' then return value end
    for _,store in ipairs(value.stores) do
        if type(store)=='table' then
            store.hostages=nil
            store.props={}
            store.settings=settings(store.settings,false)
            for _,register in ipairs(type(store.registers)=='table' and store.registers or {}) do
                if type(register)=='table' and type(register.visual)=='table' then
                    local visual={}
                    for _,key in ipairs({'x','y','z','heading','placement','autoLocate'}) do visual[key]=D.copy(register.visual[key]) end
                    register.visual=visual
                end
            end
            for _,safe in ipairs(type(store.safes)=='table' and store.safes or {}) do
                if type(safe)=='table' then
                    safe.visual=nil
                    safe.itemRequirements=nil
                    if safe.minigame then safe.minigame=game(safe.minigame) end
                end
            end
        end
    end
    return value
end
function L.administration(value,current)
    if type(value)~='table' then return value end
    local result=D.copy(current)
    for _,key in ipairs({'language','framework','inventory','policeJobs','notifications','debug'}) do result[key]=D.copy(value[key]) end
    -- Les exports personnalisés ne sont pas proposés en Light.
    if result.inventory=='custom' then result.inventory='auto' end
    result.target=false
    result.policeCanRob=true
    return result
end
return L
