-- Représentation locale des coffres ouvrants et des lots réels du serveur.
MarketSafes={}
local M=MarketSafes
local Loot=require 'shared.loot'
local function safeDebug(event,detail)
    if not Config or Config.debug~=true then return end
    print('[cdt_marketrobbery_light][debug][client][coffre] '..event..' '..json.encode(detail or {}))
end
local stores={}
local function rotate(p,h,x,y,z)
    local a=math.rad(h);return {x=p.x+x*math.cos(a)-y*math.sin(a),y=p.y+x*math.sin(a)+y*math.cos(a),z=p.z+z}
end
local function create(model,p,h,fallback)
    local hash=joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        if fallback then return create(fallback,p,h) end
        return nil
    end
    local ok=pcall(lib.requestModel,hash,5000);if not ok then return nil end
    local entity=CreateObjectNoOffset(hash,p.x,p.y,p.z,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    if entity==0 then return nil end
    SetEntityHeading(entity,h);SetEntityCollision(entity,false,false);SetEntityInvincible(entity,true)
    return entity
end
local function destroy(r)
    for _,entity in pairs(r.items or {}) do DeleteEntity(entity) end
    for _,entity in pairs(r.hands or {}) do DeleteEntity(entity) end
    if r.door then if r.ownDoor then DeleteEntity(r.door) else SetEntityHeading(r.door,r.closedHeading) end end
    if r.body and r.ownBody then DeleteEntity(r.body) end
    if r.hidden then local h=r.hidden;RemoveModelHide(h.x,h.y,h.z,0.4,h.model,true) end
end
function M.remove(id)
    local record=stores[id];if not record then return end
    stores[id]=nil;for _,r in pairs(record.safes) do destroy(r) end
end
function M.ensure(store)
    local previous=stores[store.id]
    if previous then
        if not previous.retryAt or GetGameTimer()<previous.retryAt then return end
        M.remove(store.id)
    end
    local record={safes={},state=nil};stores[store.id]=record
    for _,safe in ipairs(store.safes or {}) do
        local v=safe.visual or {}
        local r={config=safe,items={},hands={},positions={},initialAmounts={},angle=0,initialized=false};record.safes[safe.id]=r
        local bodyModel=v.bodyModel or 'bkr_prop_biker_safebody_01a'
        local doorModel=v.doorModel or (bodyModel=='ch_prop_ch_arcade_safe_body' and 'ch_prop_ch_arcade_safe_door' or 'bkr_prop_biker_safedoor_01a')
        if not IsModelInCdimage(joaat(bodyModel)) or not IsModelValid(joaat(bodyModel)) or not IsModelInCdimage(joaat(doorModel)) or not IsModelValid(joaat(doorModel)) then
            safeDebug('model_fallback',{store=store.id,point=safe.id,bodyModel=bodyModel,doorModel=doorModel})
            bodyModel='bkr_prop_biker_safebody_01a';doorModel='bkr_prop_biker_safedoor_01a'
        end
        local source=GetClosestObjectOfType(safe.x,safe.y,safe.z,0.5,joaat(safe.model),false,false,false)
        local sourcePosition=source~=0 and GetEntityCoords(source) or nil
        if not safe.spawnProp and safe.model==bodyModel and source~=0 then r.body=source;r.ownBody=false
        else
            local p={x=safe.x,y=safe.y,z=safe.z}
            -- Masquer l'original avant les sondes, afin qu'il ne bloque pas la pose.
            if not safe.spawnProp and source~=0 then
                local old=sourcePosition;r.hidden={x=old.x,y=old.y,z=old.z,model=joaat(safe.model)}
                CreateModelHide(old.x,old.y,old.z,0.4,r.hidden.model,true)
            end
            r.body=create(bodyModel,p,safe.heading);r.ownBody=true
            if stores[store.id]~=record then destroy(r);return end
            if r.body then
                local ground=safe.placement
                if not ground and source~=0 then ground=MarketGround.contact(joaat(safe.model),sourcePosition,safe.heading) end
                local data=ground and MarketGround.origin(joaat(bodyModel),ground,safe.heading) or p
                data.heading=safe.heading
                -- Les anciens points peuvent être au centre du modèle : rechercher le sol proche.
                if not safe.placement then data.placement=nil end
                if not MarketGround.settle(r.body,data,false) then DeleteEntity(r.body);r.body=nil end
            end
            if r.body and not r.hidden and not safe.spawnProp and safe.model~=bodyModel then
                local p=sourcePosition or safe
                r.hidden={x=p.x,y=p.y,z=p.z,model=joaat(safe.model)}
                CreateModelHide(p.x,p.y,p.z,0.4,r.hidden.model,true)
            end
        end
        if stores[store.id]~=record then destroy(r);return end
        if r.body then
            r.origin=GetEntityCoords(r.body);r.heading=safe.heading
            local low,high=GetModelDimensions(joaat(bodyModel))
            r.low=low;r.high=high
            local existing=not safe.spawnProp and GetClosestObjectOfType(safe.x,safe.y,safe.z,1.5,joaat(doorModel),false,false,false) or 0
            if existing~=0 then r.door=existing;r.ownDoor=false;r.closedHeading=GetEntityHeading(existing)
            else
                local loaded=pcall(lib.requestModel,joaat(doorModel),5000)
                if loaded then
                    local dlow,dhigh=GetModelDimensions(joaat(doorModel))
                    -- Aligner les faces avant, avec un léger retrait dans le cadre.
                    -- Utiliser le bord arrière de la porte la déportait vers
                    -- l'extérieur de toute son épaisseur (poignée comprise).
                    -- Conserver l'origine propre du modèle pour son pivot.
                    local p=rotate(r.origin,safe.heading,(low.x+high.x-dlow.x-dhigh.x)/2+(v.doorOffsetX or 0),low.y+0.02-dlow.y+(v.doorOffsetY or 0),(low.z+high.z-dlow.z-dhigh.z)/2+(v.doorOffsetZ or 0))
                    r.door=create(doorModel,p,safe.heading);r.ownDoor=true;r.closedHeading=safe.heading
                end
            end
            if r.door then FreezeEntityPosition(r.door,true) end
            if not r.door then destroy(r);r.body=nil;r.hidden=nil;safeDebug('door_unavailable',{store=store.id,point=safe.id,model=doorModel}) end
        else safeDebug('body_unavailable',{store=store.id,point=safe.id,model=bodyModel}) end
        safeDebug('entities',{store=store.id,point=safe.id,body=r.body,door=r.door,retry=not r.body or not r.door})
        if not r.body or not r.door then
            if r.hidden then local h=r.hidden;RemoveModelHide(h.x,h.y,h.z,0.4,h.model,true);r.hidden=nil end
            record.retryAt=GetGameTimer()+5000
        end
        if stores[store.id]~=record then destroy(r);return end
    end
end
function M.sync(id,state)if stores[id] then stores[id].state=state end end
local function slot(r,index)
    local low,high,v=r.low,r.high,r.config.visual or {}
    local col=(index-1)%3
    local row=math.floor((index-1)/3)%2
    local layer=math.floor((index-1)/6)
    local x=low.x+(high.x-low.x)*(0.25+col*0.25)
    local y=low.y+(high.y-low.y)*(0.3+row*0.25)
    local z=low.z+(high.z-low.z)*0.18+layer*math.min(0.11,(high.z-low.z)*0.1)
    return rotate(r.origin,r.heading,x+(v.lootOffsetX or 0),y+(v.lootOffsetY or 0),z+(v.lootOffsetZ or 0))
end
function M.points(id)
    local points={};local record=stores[id];if not record or not record.state then return points end
    for safeId,r in pairs(record.safes) do
        local state=record.state.safes[safeId]
        if Loot.viewable(record.state,safeId) and r.body and r.door then
            local p=r.origin
            points[#points+1]={id=safeId,x=p.x,y=p.y,z=p.z,label='Inventaire · '..(r.config.label or safeId)}
        end
    end
    return points
end
function M.open(id,safeId,isCurrent)
    local record=stores[id];local r=record and record.safes[safeId]
    if not r or not r.body or not r.door then return false end
    local dict='mini@safe_cracking'
    local ok=pcall(lib.requestAnimDict,dict,5000)
    if not ok or stores[id]~=record or isCurrent and not isCurrent() then return false end
    local actor=PlayerPedId()
    TaskTurnPedToFaceCoord(actor,r.origin.x,r.origin.y,r.origin.z,300);Wait(300)
    if stores[id]~=record or isCurrent and not isCurrent() then return false end
    TaskPlayAnim(actor,dict,'door_open_succeed_stand',4.0,-4.0,4200,0,0,false,false,false)
    -- Laisser le personnage saisir la poignée avant la confirmation serveur,
    -- qui déclenche la rotation de la porte pour tous les observateurs.
    Wait(2050)
    return stores[id]==record and (not isCurrent or isCurrent())
end
function M.ready(id,safeId)
    local r=stores[id] and stores[id].safes[safeId]
    return r and r.body and r.door and DoesEntityExist(r.body) and DoesEntityExist(r.door) or false
end
function M.play(id,safeId,isCurrent)
    local record=stores[id];local r=record and record.safes[safeId]
    if not r or not r.body or not r.door then return false end
    local ok=pcall(lib.requestAnimDict,'anim@heists@ornate_bank@grab_cash',5000);if not ok then return false end
    if stores[id]~=record or isCurrent and not isCurrent() then return false end
    local actor=PlayerPedId()
    TaskTurnPedToFaceCoord(actor,r.origin.x,r.origin.y,r.origin.z,300);Wait(300)
    if stores[id]~=record or isCurrent and not isCurrent() then return false end
    TaskPlayAnim(actor,'anim@heists@ornate_bank@grab_cash','grab',4.0,-4.0,-1,49,0,false,false,false)
    Wait(0);if isCurrent and not isCurrent() then return false end;SetEntityAnimCurrentTime(actor,'anim@heists@ornate_bank@grab_cash','grab',0.2)
    return true
end
CreateThread(function()
    while true do
        local delay=200
        for id,record in pairs(stores) do
            for safeId,r in pairs(record.safes) do
                local state=record.state and record.state.safes[safeId]
                if r.body and r.door and state then
                    local configured=(r.config.visual or {}).openAngle or 70
                    local target=state.openedAt and math.min(80,math.abs(configured)) or 0
                    -- Une arrivée tardive doit retrouver la porte dans son état courant.
                    if not r.initialized then
                        local age=state.openedAt and GetGameTimer()/1000+(M.offset or 0)-state.openedAt or 0
                        r.angle=age>3 and target or 0;SetEntityHeading(r.door,r.closedHeading+r.angle);r.initialized=true
                    end
                    if math.abs(r.angle-target)>0.01 then
                        if not r.motion or r.motion.target~=target then r.motion={from=r.angle,target=target,started=GetGameTimer()} end
                        local t=math.min(1,(GetGameTimer()-r.motion.started)/1800)
                        r.angle=r.motion.from+(target-r.motion.from)*(t*t*(3-2*t))
                        SetEntityHeading(r.door,r.closedHeading+r.angle);delay=0
                    else
                        r.motion=nil
                    end
                    local wanted,wantedHands={},{}
                    for index,chunk in ipairs(state.chunks or {}) do
                        local key=chunk.id;local p=slot(r,index);r.positions[key]=p
                        local activity=record.state.activities and record.state.activities['collect:'..safeId..':'..key]
                        -- Le début est exprimé en temps serveur, recalé par M.clock.
                        local elapsed=activity and math.max(0,GetGameTimer()/1000+(M.offset or 0)-activity.startedAt) or 0
                        local inHand=activity and elapsed>=activity.duration*0.4
                        if chunk.status~='taken' then
                            -- Le stock initial persiste côté serveur : même diminution pour
                            -- tous les observateurs et les connexions tardives.
                            r.initialAmounts[key]=chunk.initialAmount or r.initialAmounts[key] or chunk.amount
                            local initial=math.max(1,r.initialAmounts[key])
                            local capacity=math.min(3,initial)
                            local visible=math.min(capacity,math.ceil(capacity*chunk.amount/initial))
                            for index=1,visible do
                                local itemKey=index==1 and key or key..':'..index
                                wanted[itemKey]=true
                                if not r.items[itemKey] then
                                    local position={x=p.x,y=p.y,z=p.z+(index-1)*0.045}
                                    local entity=create(chunk.model,position,r.heading,'prop_cs_cardbox_01')
                                    if stores[id]~=record or record.state.safes[safeId]~=state then if entity then DeleteEntity(entity) end
                                    else r.items[itemKey]=entity;if entity then FreezeEntityPosition(entity,true) end end
                                end
                                if r.items[itemKey] then SetEntityVisible(r.items[itemKey],not (inHand and index==visible),false) end
                            end
                        end
                        if inHand and chunk.status=='reserved' then
                            local player=GetPlayerFromServerId(activity.player);local actor=player~=-1 and GetPlayerPed(player) or 0
                            if r.hands[key] and r.handActors and r.handActors[key]~=actor then DeleteEntity(r.hands[key]);r.hands[key]=nil end
                            if actor~=0 and DoesEntityExist(actor) then wantedHands[key]=true end
                            if actor~=0 and DoesEntityExist(actor) and not r.hands[key] then
                                local entity=create(chunk.model,p,r.heading,'prop_cs_cardbox_01')
                                if stores[id]~=record or not record.state.activities or record.state.activities['collect:'..safeId..':'..key]~=activity then if entity then DeleteEntity(entity) end
                                elseif entity then r.hands[key]=entity;r.handActors=r.handActors or {};r.handActors[key]=actor;AttachEntityToEntity(entity,actor,GetPedBoneIndex(actor,57005),0.1,0.02,0.0,0.0,0.0,0.0,false,false,false,false,2,true) end
                            end
                        elseif r.hands[key] then DeleteEntity(r.hands[key]);r.hands[key]=nil end
                    end
                    for key,entity in pairs(r.hands) do if not wantedHands[key] then DeleteEntity(entity);r.hands[key]=nil end end
                    for key,entity in pairs(r.items) do if not wanted[key] then DeleteEntity(entity);r.items[key]=nil end end
                end
            end
        end
        Wait(delay)
    end
end)
function M.clock(serverTime)if serverTime then M.offset=serverTime-GetGameTimer()/1000 end end
AddEventHandler('onResourceStop',function(resource)if resource==GetCurrentResourceName() then for id in pairs(stores) do M.remove(id) end end end)
