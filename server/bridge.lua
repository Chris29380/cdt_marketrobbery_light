local B = {}
local custom
local Inventories=require 'shared.inventories'
local Adapters=require 'server.inventory_adapters'
local function itemName(name)
    local spec=Inventories[B.inventory]
    if name:sub(1,7):lower()=='weapon_' and spec and spec.weaponCase then return spec.weaponCase=='upper' and name:upper() or name:lower() end
    return name
end
local function started(r) return GetResourceState(r)=='started' end
local function customCall(method,...)
    if custom.resource and not started(custom.resource) then return nil end
    local ok,result=pcall(custom[method],...)
    if not ok then if Config.debug==true then print('[cdt_marketrobbery_light][debug][inventory] '..tostring(B.inventory)..' / '..method..' : '..tostring(result)) end;return nil end
    return result
end
function B.init()
    custom=nil
    local requested=Config.framework
    if requested=='auto' then
        if (started('qbx_core') or started('qb-core')) and started('es_extended') then error('Plusieurs frameworks actifs. Choisir Config.framework.') end
        requested=started('qbx_core') and 'qbox' or started('qb-core') and 'qbcore' or started('es_extended') and 'esx' or nil
    end
    assert(requested,'Aucun framework disponible.')
    B.framework=requested
    if requested=='esx' then B.core=exports.es_extended:getSharedObject()
    elseif requested=='qbcore' then B.core=exports['qb-core']:GetCoreObject()
    elseif requested~='qbox' or not started('qbx_core') then error('Framework indisponible.') end
    B.inventory=Config.inventory
    if B.inventory=='auto' then
        local found
        for _,name in ipairs({'ox','qb','qs','origen','core','tgiann','jaksam'})do
            if started(Inventories[name].resource) then
                assert(not found,'Plusieurs inventaires actifs. Choisir Config.inventory.')
                found=name
            end
        end
        B.inventory=found or 'framework'
    end
    assert(Inventories[B.inventory],'Inventaire non reconnu.')
    if Adapters.supports(B.inventory) then
        assert(started(Inventories[B.inventory].resource),'Démarrer la ressource de l’inventaire sélectionné avant le script.')
        custom=Adapters.build(B.inventory)
    end
    if B.inventory=='custom' then
        if Config.inventoryCustom and Config.inventoryCustom.mode=='exports'then custom=require('server.inventory_configured').build(Config.inventoryCustom)
        else custom=require 'server.inventory_custom'end
        assert(type(custom)=='table' and custom.configured==true,'Configurer server/inventory_custom.lua avant d’activer le bridge personnalisé.')
        for _,method in ipairs({'count','canCarry','add','remove'}) do assert(type(custom[method])=='function','Fonction manquante dans le bridge inventaire : '..method) end
        assert(custom.hasWeapon==nil or type(custom.hasWeapon)=='function','hasWeapon doit être une fonction.')
        assert(custom.resource==nil or type(custom.resource)=='string' and #custom.resource>0 and started(custom.resource),'Démarrer la ressource de l’inventaire personnalisé avant le script.')
    end
    if B.inventory=='ox' then assert(started('ox_inventory'),'Démarrer ox_inventory avant cdt_marketrobbery_light.') end
    if B.inventory=='qb' then assert(started('qb-inventory'),'Démarrer qb-inventory avant cdt_marketrobbery_light.') end
    if B.framework=='qbox' and B.inventory=='framework' then error('Qbox nécessite un inventaire pris en charge.') end
end
function B.player(src)
    if B.framework=='qbox' then return exports.qbx_core:GetPlayer(src) end
    if B.framework=='qbcore' then return B.core.Functions.GetPlayer(src) end
    return B.core.GetPlayerFromId(src)
end
function B.job(src)
    local p=B.player(src); if not p then return nil end
    local j=B.framework=='esx' and p.getJob() or p.PlayerData.job
    return j and j.name, j and j.onduty ~= false
end
function B.police(src)
    local name,duty=B.job(src); return name and Config.policeJobs[name] and duty or false
end
function B.policeJob(src)
    local name=B.job(src)
    return name~=nil and Config.policeJobs[name]==true
end
function B.canRob(src)
    return Config.policeCanRob~=false or not B.policeJob(src)
end
function B.policeCount()
    local n=0; for _, src in ipairs(GetPlayers()) do if B.police(tonumber(src)) then n=n+1 end end; return n
end
function B.admin(src)
    if IsPlayerAceAllowed(src,Config.adminAce) then return true end
    -- Les principaux group.owner/group.admin héritent des droits ACE owner/admin.
    for group,enabled in pairs(Config.adminGroups)do
        if enabled and (IsPlayerAceAllowed(src,group) or IsPlayerAceAllowed(src,'group.'..group))then return true end
    end
    local p=B.player(src); if not p then return false end
    if B.framework=='esx' then return Config.adminGroups[p.getGroup()] == true end
    if B.framework=='qbcore' then
        for group,enabled in pairs(Config.adminGroups) do if enabled and B.core.Functions.HasPermission(src,group) then return true end end
    end
    -- Qbox : permissions ACE, pas de dépendance à une ancienne API de groupes.
    return false
end
function B.count(src,name)
    name=itemName(name)
    if custom then
        local count=customCall('count',src,name)
        return type(count)=='number' and count>=0 and count<math.huge and count%1==0 and count or 0
    end
    if B.inventory=='ox' then
        -- Cette version d'ox_inventory indexe les armes en majuscules, y compris
        -- la clé de retour de Search pour une recherche portant sur un seul nom.
        if name:sub(1,7):lower()=='weapon_' then name=name:upper() end
        return exports.ox_inventory:Search(src,'count',name) or 0
    end
    if B.inventory=='qb' then return exports['qb-inventory']:GetItemCount(src,name) or 0 end
    local p=B.player(src); if not p then return 0 end
    if B.framework=='esx' then local i=p.getInventoryItem(name); return i and i.count or 0 end
    if p.PlayerData.items then
        local total=0;for _,item in pairs(p.PlayerData.items)do if item.name==name then total=total+(item.amount or 0)end end;return total
    end
    local i=p.Functions.GetItemByName(name); return i and i.amount or 0
end
function B.weapon(src,name)
    local p=B.player(src); if not p then return false end
    if B.inventory=='custom' and custom.hasWeapon then return customCall('hasWeapon',src,name)==true end
    if B.framework=='esx' and B.inventory=='framework' and p.hasWeapon(name) then return true end
    return B.count(src,name:lower())>0
end
function B.remove(src,name,count)
    if type(count)~='number' or count<=0 or count>=math.huge or count%1~=0 then return false end
    name=itemName(name)
    if B.count(src,name)<count then return false end
    if custom then return customCall('remove',src,name,count)==true end
    if B.inventory=='ox' then return exports.ox_inventory:RemoveItem(src,name,count)==true end
    if B.inventory=='qb' then return exports['qb-inventory']:RemoveItem(src,name,count,false,'cdt_marketrobbery_light')==true end
    local p=B.player(src)
    if not p then return false end
    if B.framework=='esx' then local before=B.count(src,name);p.removeInventoryItem(name,count);return B.count(src,name)==before-count end
    return p.Functions.RemoveItem(name,count)==true
end
function B.addItem(src,name,count)
    if type(count)~='number' or count<=0 or count>=math.huge or count%1~=0 then return false end
    name=itemName(name)
    if custom then
        if customCall('canCarry',src,name,count)~=true then return false end
        return customCall('add',src,name,count)==true
    end
    if B.inventory=='ox' then return exports.ox_inventory:AddItem(src,name,count)==true end
    if B.inventory=='qb' then return exports['qb-inventory']:AddItem(src,name,count,false,false,'cdt_marketrobbery_light')==true end
    local p=B.player(src); if not p then return false end
    if B.framework=='esx' then
        if p.canCarryItem and not p.canCarryItem(name,count) then return false end
        local before=B.count(src,name);p.addInventoryItem(name,count);return B.count(src,name)==before+count
    end
    return p.Functions.AddItem(name,count)==true
end
local function inventoryAccount(account)
    if B.framework~='esx' or B.inventory~='ox' then return false end
    local accounts={'money','black_money'}
    if type(GetConvar)=='function' and json then
        local ok,value=pcall(json.decode,GetConvar('inventory:accounts','["money","black_money"]'))
        if ok and type(value)=='table' then accounts=value end
    end
    for _,name in ipairs(accounts)do if name==account then return true end end
    return false
end
function B.reward(src,reward,amount)
    if reward.kind=='item' then return B.addItem(src,reward.name,amount) end
    local p=B.player(src); if not p then return false end
    if B.framework=='esx' then
        local account=reward.name=='cash' and 'money' or reward.name
        local before=p.getAccount(account)
        if not before or type(before.money)~='number' then return false end
        if inventoryAccount(account) and exports.ox_inventory:CanCarryItem(src,account,amount)~=true then return false end
        local balance=before.money
        p.addAccountMoney(account,amount,'cdt_marketrobbery_light')
        local after=p.getAccount(account)
        return after~=nil and after.money==balance+amount
    end
    return p.Functions.AddMoney(reward.name,amount,'cdt_marketrobbery_light')==true
end
function B.canReward(src,reward,amount)
    local p=B.player(src); if not p then return false end
    if reward.kind=='item' then
        local name=itemName(reward.name)
        if custom then return customCall('canCarry',src,name,amount)==true end
        if B.inventory=='ox' then return exports.ox_inventory:CanCarryItem(src,name,amount)==true end
        if B.inventory=='qb' then return exports['qb-inventory']:CanAddItem(src,name,amount)==true end
        if B.framework=='esx' then return not p.canCarryItem or p.canCarryItem(name,amount)==true end
        -- Sans API de capacité, l'ajout reste vérifié ; l'échec sera journalisé sans rejeu.
        return true
    end
    if B.framework=='esx' then
        local account=reward.name=='cash' and 'money' or reward.name
        if not p.getAccount(account) then return false end
        return not inventoryAccount(account) or exports.ox_inventory:CanCarryItem(src,account,amount)==true
    end
    return p.PlayerData.money[reward.name]~=nil
end
return B
