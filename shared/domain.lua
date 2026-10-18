-- Logique pure, utilisable dans FiveM et dans les tests Lua.
local D = {}
local S = require 'shared.safes'
local R = require 'shared.registers'
function D.copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for k, v in pairs(value) do out[k] = D.copy(v) end; return out
end
function D.settings(config, store)
    local result = D.copy(config.defaults)
    for k, v in pairs(store.settings or {}) do result[k] = D.copy(v) end
    return result
end
function D.distance(a, b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end
function D.angle(a, b) return math.abs((a-b+180)%360-180) end
function D.state(store)
    local r = {}; for _, p in ipairs(store.registers) do r[p.id] = 'ready' end
    local safes={}; for _, s in ipairs(store.safes or {}) do safes[s.id]={status='ready',failures=0,retryAt=0} end
    return { phase = 'available', registers = r, safes=safes, cooldownUntil = 0, revision = 0 }
end
function D.requirements(rule, hasWeapon, selected, count, countRequirement)
    local weapons = rule.weapons or {}
    if #weapons > 0 then
        local matched = 0
        for _, w in ipairs(weapons) do if hasWeapon(w) then matched = matched+1 end end
        if rule.weaponMode == 'all' and matched ~= #weapons or rule.weaponMode ~= 'all' and matched == 0 then return false, 'Arme requise manquante.' end
        if rule.equipped then
            local equipped = false; for _, w in ipairs(weapons) do if selected(w) then equipped = true end end
            if not equipped then return false, 'Équipe une arme autorisée.' end
        end
    end
    local items, matched = rule.items or {}, {}
    for _, item in ipairs(items) do local quantity=countRequirement and countRequirement(item) or count(item.name);if quantity >= item.count then matched[#matched+1] = item end end
    if #items > 0 and (rule.itemMode == 'any' and #matched == 0 or rule.itemMode ~= 'any' and #matched ~= #items) then return false, 'Objet requis manquant.' end
    if rule.itemMode == 'any' and #matched > 1 then matched = { matched[1] } end
    return true, matched
end
function D.allRegisters(state)
    for _, status in pairs(state.registers) do if status ~= 'looted' then return false end end; return true
end
function D.completed(store, state)
    if not D.allRegisters(state) then return false end
    for _,bag in pairs(state.bags or {}) do if bag.status~='taken' then return false end end
    for _, safe in ipairs(store.safes or {}) do if not state.safes[safe.id] or state.safes[safe.id].status~='looted' then return false end end
    return true
end
function D.validate(config)
    if type(config) ~= 'table' or type(config.stores) ~= 'table' or type(config.defaults) ~= 'table' then return false, 'Structure de configuration invalide.' end
    local function number(v, lo, hi) return type(v) == 'number' and v == v and v >= lo and v <= hi end
    local function integer(v, lo, hi) return number(v, lo, hi) and v%1 == 0 end
    local function name(v) return type(v) == 'string' and #v > 0 and #v <= 80 and v:match('^[%w_%-]+$') end
    local function point(p)
        if not (type(p) == 'table' and number(p.x,-16000,16000) and number(p.y,-16000,16000) and number(p.z,-1000,3000)) then return false end
        local v=p.placement
        return v==nil or type(v)=='table' and number(v.x,-16000,16000) and number(v.y,-16000,16000) and number(v.z,-1000,3000)
    end
    local ranges = { minPolice={0,200}, cooldown={0,604800}, globalCooldown={0,604800}, maxDuration={60,7200}, abandonDelay={10,3600}, maxActive={1,50}, alertChance={0,100}, alertDelay={0,300}, refusalChance={0,100}, intimidateDuration={2,120}, registerDuration={2,300}, safeSteps={1,8}, safeTolerance={2,25}, safeDuration={15,600}, safeAttempts={1,20}, safePenalty={0,600} }
    local function settings(s)
        for key, range in pairs(ranges) do if not integer(s[key],range[1],range[2]) then return false, 'Réglage invalide : '..key end end
        if type(s.safeRequiresRegisters) ~= 'boolean' then return false, 'Condition du coffre invalide.' end
        for _, key in ipairs({'registerReward','safeReward'}) do
            local r=s[key]
            if type(r)~='table' or (r.kind~='money' and r.kind~='item') or not name(r.name) or not integer(r.min,1,100000) or not integer(r.max,r.min,100000) then return false,'Récompense invalide : '..key end
        end
        if s.safeMinigame~=nil or s.safeLoot~=nil then
            local probe={id='validation',label='Validation',x=0,y=0,z=0,interaction={x=0,y=0,z=0},model='prop_ld_int_safe_01',heading=0,spawnProp=false,requiresRegisters=true,
                minigame=s.safeMinigame or {type='dial',difficulty='normal'},loot=s.safeLoot or {}}
            local valid,why=S.validate(probe,{x=0,y=0,z=0},10); if not valid then return false,why end
        end
        if type(s.requirements)~='table' then return false,'Conditions manquantes.' end
        for _, stage in ipairs({'intimidate','register','safe'}) do
            local r=s.requirements[stage]
            if type(r)~='table' or (r.weaponMode~='all' and r.weaponMode~='any') or (r.itemMode~='all' and r.itemMode~='any') or type(r.equipped)~='boolean' or type(r.weapons)~='table' or type(r.items)~='table' or #r.weapons>30 or #r.items>20 then return false,'Conditions invalides : '..stage end
            local seen={}
            for _, w in ipairs(r.weapons) do if not name(w) or seen[w] then return false,'Arme invalide ou répétée.' end; seen[w]=true end
            seen={}
            for _, i in ipairs(r.items) do
                if type(i)~='table' or not name(i.name) or i.kind~=nil and i.kind~='item' and i.kind~='weapon' or not integer(i.count,1,100) or not ({never=true,start=true,success=true,failure=true})[i.consume] then return false,'Objet invalide ou répété.' end
                local key=(i.kind=='weapon' or i.name:sub(1,7):lower()=='weapon_') and i.name:lower() or i.name
                if seen[key] then return false,'Objet invalide ou répété.' end
                seen[key]=true
            end
        end
        return true
    end
    local ok, err=settings(config.defaults); if not ok then return false,err end
    if #config.stores>100 then return false,'Maximum 100 magasins.' end
    local ids={}
    for _, store in ipairs(config.stores) do
        if type(store)~='table' or not name(store.id) or ids[store.id] then return false,'Identifiant magasin invalide ou répété.' end
        ids[store.id]=true
        if type(store.label)~='string' or #store.label<1 or #store.label>100 or type(store.enabled)~='boolean' or not point(store.center) or not number(store.radius,3,80) then return false,'Zone ou nom invalide : '..store.id end
        if store.location~=nil then
            local l=store.location
            if type(l)~='table' or type(l.interiorHash)~='string' or #l.interiorHash>32 or type(l.mapping)~='string' or #l.mapping>100 or type(l.address)~='string' or #l.address>150 then return false,'Identité de l’intérieur invalide : '..store.id end
        end
        if not point(store.clerk) or not name(store.clerk.model) or not number(store.clerk.heading,0,360) then return false,'Commerçant invalide.' end
        if D.distance(store.center,store.clerk)>store.radius then return false,'Commerçant hors de la zone.' end
        if type(store.registers)~='table' or #store.registers<1 or #store.registers>10 or type(store.props)~='table' or #store.props>30 or type(store.settings)~='table' then return false,'Points du magasin invalides.' end
        local points={}
        for _, p in ipairs(store.registers) do
            if not point(p) or not name(p.id) or points[p.id] or D.distance(store.center,p)>store.radius then return false,'Caisse invalide ou hors zone.' end; points[p.id]=true
            local valid,why=R.validate(p); if not valid then return false,why end
            if p.bag and (not point(p.bag.drop) or D.distance(store.center,p.bag.drop)>store.radius) then return false,'Le point de dépôt du sac doit rester dans la supérette.' end
        end
        if store.safe~=nil or type(store.safes)~='table' or #store.safes>12 then return false,'Liste de coffres invalide (maximum 12).' end
        local safeIds={}
        for _, safe in ipairs(store.safes) do
            local valid,why=S.validate(type(safe)=='table' and S.effective(safe,D.settings(config,store)) or safe,store.center,store.radius); if not valid then return false,('Supérette %s, coffre %s : %s'):format(store.id,type(safe)=='table' and tostring(safe.id) or '?',why) end
            if safeIds[safe.id] then return false,'Identifiant de coffre répété.' end
            safeIds[safe.id]=true
        end
        for _, p in ipairs(store.props) do if not point(p) or not name(p.model) or not number(p.heading,0,360) or D.distance(store.center,p)>store.radius then return false,'Prop invalide ou hors zone.' end end
        for key in pairs(store.settings) do if config.defaults[key]==nil then return false,'Réglage inconnu : '..tostring(key) end end
        ok,err=settings(D.settings(config,store)); if not ok then return false,store.id..' : '..err end
    end
    return true
end
return D
