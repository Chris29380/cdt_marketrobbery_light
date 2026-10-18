local M={}
-- La collecte reste dans notre NUI : sa durée ne dépend pas des callbacks
-- de fin d'animation d'une autre interface de progression.
function M.progress(duration,isCurrent)
    local started=GetGameTimer()
    local lastUpdate=-100
    local previousBusy=LocalPlayer.state.invBusy
    LocalPlayer.state.invBusy=true
    local ok,success,reason=xpcall(function()
        while true do
            if not isCurrent() then return false,'session_closed' end
            local ped=PlayerPedId()
            if IsEntityDead(ped) then return false,'dead' end
            if IsPedRagdoll(ped) then return false,'ragdoll' end
            if IsPedCuffed(ped) then return false,'cuffed' end
            if IsPedFalling(ped) then return false,'falling' end
            if IsPedSwimming(ped) then return false,'swimming' end
            if IsDisabledControlJustPressed(0,73) then return false,'cancelled' end
            local elapsed=GetGameTimer()-started
            if elapsed>=duration then return true end
            for _,control in ipairs({21,30,31,36,63,64,71,72,75,25}) do DisableControlAction(0,control,true) end
            DisablePlayerFiring(PlayerId(),true)
            if elapsed-lastUpdate>=100 then
                lastUpdate=elapsed
                SendNUIMessage({type='inventoryProgress',percent=math.floor(elapsed/duration*100)})
            end
            Wait(0)
        end
    end,debug.traceback)
    LocalPlayer.state.invBusy=previousBusy
    if not ok then error(success,0) end
    return success,reason
end
local function imagePath(base,image)
    if image:match('^nui://') then return image:gsub('^nui://([^/]+)','https://cfx-nui-%1') end
    if image:match('^https?://') then return image end
    local path=base:gsub('/+$','')..'/'..image
    return (path:gsub('^nui://([^/]+)','https://cfx-nui-%1'))
end
function M.prepare(view,inventoryType)
    local out={};for k,v in pairs(view)do out[k]=v end;out.chunks={}
    local ox=(not inventoryType or inventoryType=='ox') and GetResourceState('ox_inventory')=='started'
    local qb=(not inventoryType or inventoryType=='qb' or inventoryType=='framework') and GetResourceState('qb-core')=='started'
    local core
    local customBase=Config and Config.inventoryImagePaths and Config.inventoryImagePaths[inventoryType]
    local definitions
    if inventoryType=='qs' and GetResourceState('qs-inventory')=='started' then
        local ok,value=pcall(function()return exports['qs-inventory']:GetItemList()end);if ok then definitions=value end
    elseif inventoryType=='core' and GetResourceState('core_inventory')=='started' then
        local ok,value=pcall(function()return exports.core_inventory:getItemsList()end);if ok then definitions=value end
    end
    if qb then local ok,value=pcall(function()return exports['qb-core']:GetCoreObject()end);if ok then core=value end end
    for _,lot in ipairs(view.chunks or {})do
        local entry={};for k,v in pairs(lot)do entry[k]=v end
        local item,base
        if ox then
            local ok,value=pcall(function()return exports.ox_inventory:Items(lot.name)end)
            if ok then item=value end
            base=GetConvar('inventory:imagepath','nui://ox_inventory/web/images')
        elseif core then item=core.Shared and core.Shared.Items and core.Shared.Items[lot.name];base='nui://qb-inventory/html/images'
        elseif inventoryType=='qb' then base='nui://qb-inventory/html/images'
        elseif type(definitions)=='table' then item=definitions[lot.name] end
        if type(customBase)=='string' and customBase~='' then base=customBase end
        if type(item)=='table' then
            if not entry.label or entry.label==entry.name then entry.label=item.label or entry.label end
            local image=item.client and item.client.image or item.image or (item.name or lot.name)..'.png'
            if type(image)=='string' and base then entry.image=imagePath(base,image) end
        elseif base and type(lot.name)=='string' and lot.name:match('^[%w_%-]+$') then
            entry.image=imagePath(base,(lot.kind=='money' and (lot.name=='cash' or lot.name=='money') and 'money' or lot.name)..'.png')
        end
        out.chunks[#out.chunks+1]=entry
    end
    return out
end
return M
