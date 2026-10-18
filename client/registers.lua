-- Le commerçant local, le tiroir et le sac suivent la même activité serveur.
-- Aucun déplacement ou pillage de caisse n'est appliqué au joueur.
local R=require 'shared.registers'
MarketRegisters={}
local M=MarketRegisters
local stores={}
local timeOffset=0
local scanning=false

local dict='mp_am_hold_up'
local pedClip='holdup_victim_20s'
local tillClip='holdup_victim_20s_till'
-- Le sac porté utilise un modèle statique : son origine n'est pas celle du
-- modèle de scène p_poly_bag_01_s (qui se décale lorsqu'on l'attache à une main).
local function carryBag(bag,ped,right)
    AttachEntityToEntity(bag,ped,GetPedBoneIndex(ped,right and 57005 or 60309),
        0.1,right and 0.11 or -0.11,0.08,0.0,right and 75.0 or -75.0,right and 75.0 or -75.0,
        false,false,false,true,2,true)
end
local function model(name)
    local hash=joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    local ok=pcall(lib.requestModel,hash,5000); return ok and hash or nil
end
local function object(hash,p,heading)
    local entity=CreateObjectNoOffset(hash,p.x,p.y,p.z,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    if not entity or entity==0 then return nil end
    SetEntityHeading(entity,heading or 0); SetEntityCollision(entity,false,false); SetEntityInvincible(entity,true)
    return entity
end
local function sceneOrigin(anchor,heading)
    -- Inverser le transform initial du modèle, position ET orientation.
    local rotation=GetAnimInitialOffsetRotation(dict,tillClip,0.0,0.0,0.0,0.0,0.0,0.0,0,2)
    local sceneHeading=(heading-rotation.z)%360
    local offset=GetAnimInitialOffsetPosition(dict,tillClip,0.0,0.0,0.0,0.0,0.0,sceneHeading,0,2)
    return {x=anchor.x-offset.x,y=anchor.y-offset.y,z=anchor.z-offset.z},sceneHeading
end
local function setPhase(r,phase)
    SetSynchronizedScenePhase(r.drawerScene,math.max(0,math.min(0.999,phase)))
    -- Une scène figée doit conserver ses entités actives pour évaluer le tiroir.
    ForceEntityAiAndAnimationUpdate(r.till)
    if r.bag then ForceEntityAiAndAnimationUpdate(r.bag) end
end
function M.clock(serverTime) if serverTime then timeOffset=serverTime-GetGameTimer()/1000 end end
function M.ensure(store)
    local previous=stores[store.id]
    if previous then
        if not previous.retryAt or GetGameTimer()<previous.retryAt or previous.working then return end
        M.remove(store.id)
    end
    local record={id=store.id,points=store.registers,registers={},bags={},state=previous and previous.state,clerk=previous and previous.clerk,home=store.clerk}; stores[store.id]=record
    local loaded=pcall(lib.requestAnimDict,dict,5000)
    pcall(lib.requestAnimDict,'mp_common',5000)
    if not loaded then stores[store.id]=nil; print('[cdt_marketrobbery_light] Animations de caisse indisponibles.'); return end
    for _,register in ipairs(store.registers) do
        local v=R.visual(register); local anchor={x=v.x,y=v.y,z=v.z}; local heading=v.heading
        local source=R.original(register)
        local sourceHash=joaat(source.model)
        local original=GetClosestObjectOfType(source.x,source.y,source.z,register.original and 0.3 or 1.6,sourceHash,false,false,false)
        -- Attendre le décor en streaming plutôt que poser une seconde caisse
        -- à des coordonnées approximatives sans masquer la véritable caisse.
        if v.autoLocate and original==0 then record.retryAt=GetGameTimer()+5000;goto continue end
        local hiddenAt={x=source.x,y=source.y,z=source.z,model=sourceHash,radius=v.hideRadius}
        if original~=0 and DoesEntityExist(original) and GetEntityModel(original)==sourceHash then
            local p=GetEntityCoords(original)
            hiddenAt.x,hiddenAt.y,hiddenAt.z=p.x,p.y,p.z
            if v.autoLocate then anchor={x=p.x,y=p.y,z=p.z};heading=GetEntityHeading(original) end
        end
        local hash=model(R.replacementModel)
        if stores[store.id]~=record then if hash then SetModelAsNoLongerNeeded(hash) end; return end
        if hash then
            local till=object(hash,anchor,heading)
            if till then
                local origin,sceneHeading=sceneOrigin(anchor,heading)
                local scene=CreateSynchronizedScene(origin.x,origin.y,origin.z,0.0,0.0,sceneHeading,2)
                SetSynchronizedSceneHoldLastFrame(scene,true)
                local playing=PlaySynchronizedEntityAnim(till,scene,tillClip,dict,8.0,-8.0,0,0)
                if playing then
                    CreateModelHide(hiddenAt.x,hiddenAt.y,hiddenAt.z,hiddenAt.radius,hiddenAt.model,true)
                    SetSynchronizedSceneRate(scene,0.0)
                    local radians=math.rad(heading)
                    record.registers[register.id]={config=register,till=till,drawerScene=scene,anchor=anchor,heading=sceneHeading,visual=v,hiddenAt=hiddenAt,
                        origin={x=origin.x+v.offsetX*math.cos(radians)-v.offsetY*math.sin(radians),y=origin.y+v.offsetX*math.sin(radians)+v.offsetY*math.cos(radians),z=origin.z+v.offsetZ}}
                    -- Les réglages d'alignement déplacent tout l'ensemble, pas le ped seul.
                    local r=record.registers[register.id]
                    SetSynchronizedSceneOrigin(scene,r.origin.x,r.origin.y,r.origin.z,0.0,0.0,sceneHeading,false)
                    setPhase(r,0)
                else
                    DeleteEntity(till)
                    record.retryAt=GetGameTimer()+5000
                    print('[cdt_marketrobbery_light] Animation du tiroir indisponible : '..register.id)
                end
            end
        else
            record.retryAt=GetGameTimer()+5000
        end
        ::continue::
    end
end
function M.sync(id,state) if stores[id] then stores[id].state=state end end
function M.bind(id,ped,home) if stores[id] then stores[id].clerk=ped;stores[id].home=home end end
function M.scanMapping(scan)
    if scanning then return nil,'Une détection est déjà en cours.' end
    local revealed={}
    for id,store in pairs(stores) do
        if store.working then return nil,'Attends la fin du vidage des caisses avant de rescanner.' end
        for _,r in pairs(store.registers) do revealed[#revealed+1]={id=id,store=store,register=r} end
    end
    scanning=true
    for _,entry in ipairs(revealed) do
        local r=entry.register;local p=r.hiddenAt
        RemoveModelHide(p.x,p.y,p.z,p.radius,p.model,true)
        if DoesEntityExist(r.till) then SetEntityVisible(r.till,false,false) end
    end
    Wait(100)
    local ok,result,why=pcall(scan)
    for _,entry in ipairs(revealed) do
        if stores[entry.id]==entry.store then
            local r=entry.register;local p=r.hiddenAt
            CreateModelHide(p.x,p.y,p.z,p.radius,p.model,true)
            if DoesEntityExist(r.till) then SetEntityVisible(r.till,true,false) end
        end
    end
    scanning=false
    if not ok then return nil,'Détection interrompue. Les caisses ont été restaurées.' end
    return result,why
end
local function clearAccessories(r)
    if r.bag then DeleteEntity(r.bag);r.bag=nil end
    if r.cash then DeleteEntity(r.cash);r.cash=nil end
    r.cashInHand=nil;r.cashPrepared=nil
    r.activity=nil;r.stage=nil;r.dropped=nil
end
-- Conservé pour le nettoyage commun des actions ; le joueur ne joue plus cette scène.
function M.stopPlayer() end
local function restoreClerk(store)
    local ped=store.clerk
    if ped and DoesEntityExist(ped) and store.working then
        store.working=nil;ClearPedTasksImmediately(ped)
        MarketGround.settle(ped,store.home,true)
    end
end
function M.remove(id)
    local store=stores[id];if not store then return end
    stores[id]=nil
    for _,bag in pairs(store.bags) do if bag.entity then DeleteEntity(bag.entity) end end
    if store.clerk and DoesEntityExist(store.clerk) and store.working then ClearPedTasksImmediately(store.clerk) end
    for _,r in pairs(store.registers) do
        clearAccessories(r);DeleteEntity(r.till)
        RemoveModelHide(r.hiddenAt.x,r.hiddenAt.y,r.hiddenAt.z,r.hiddenAt.radius,r.hiddenAt.model,true)
    end
end
function M.ready(id,point)
    local store=stores[id]
    if not store then return false end
    if not point then
        if store.state and store.state.pausedRegister and store.state.registers[store.state.pausedRegister]=='ready' then point=store.state.pausedRegister end
        for _,register in ipairs(store.points) do
            if point then break end
            if store.state and store.state.registers[register.id]=='ready' then point=register.id;break end
        end
    end
    local r=store.registers[point]
    return r~=nil and DoesEntityExist(r.till) and store.clerk~=nil and DoesEntityExist(store.clerk)
end
function M.play(id,point,duration)
    return M.ready(id,point) and type(duration)=='number' and duration>0
end
local function walk(ped,p,heading,milliseconds)
    ClearPedTasksImmediately(ped);FreezeEntityPosition(ped,false);SetEntityCollision(ped,true,true);SetEntityHasGravity(ped,true)
    TaskFollowNavMeshToCoord(ped,p.x,p.y,p.z,1.5,math.max(1000,milliseconds),0.15,false,heading or 0)
end
local function distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
local function renderCash(r,ped,phase)
    if not r.cash then return end
    local hand=GetWorldPositionOfEntityBone(ped,GetPedBoneIndex(ped,57005))
    local bagMouth=GetWorldPositionOfEntityBone(ped,GetPedBoneIndex(ped,60309))
    -- Les contacts suivent les mains de l'animation, pas des délais arbitraires.
    -- Les billets apparaissent à la prise puis disparaissent à l'entrée du sac.
    if phase<0.45 or phase>=0.95 then r.cashInHand=false
    elseif r.cashInHand then
        if distance(hand,bagMouth)<0.22 then r.cashInHand=false end
    elseif distance(hand,GetEntityCoords(r.till))<0.5 and distance(hand,bagMouth)>0.28 then
        r.cashInHand=true
    end
    SetEntityVisible(r.cash,r.cashInHand==true,false)
end
local function renderActivity(store,r,activity,now)
    local ped=store.clerk;if not ped or not DoesEntityExist(ped) then return end
    local key=activity.startedAt..':'..activity.player
    local travel=activity.travelDuration or 1
    local duration=activity.animationDuration or math.max(1,activity.duration-2*travel-2)
    local elapsed=math.max(0,now-activity.startedAt)
    local start=GetAnimInitialOffsetPosition(dict,pedClip,r.origin.x,r.origin.y,r.origin.z,0.0,0.0,r.heading,0,2)
    local rotation=GetAnimInitialOffsetRotation(dict,pedClip,r.origin.x,r.origin.y,r.origin.z,0.0,0.0,r.heading,0,2)
    if r.activity~=key then
        clearAccessories(r);r.activity=key;store.working=true
        if MarketClerk then MarketClerk.clear(ped) end
    end
    if elapsed<travel then
        if r.stage~='walking' then r.stage='walking';walk(ped,start,rotation.z,(travel-elapsed)*1000) end
        setPhase(r,0);return
    end
    if not r.bag and not r.dropped then
        local hash=model(R.bagModel(r.config))
        if stores[store.id]~=store or not store.state or store.state.activities['register:'..activity.point]~=activity then if hash then SetModelAsNoLongerNeeded(hash) end;return end
        if hash then r.bag=object(hash,r.origin,r.heading);if r.bag then carryBag(r.bag,ped,false) end end
    end
    if elapsed<travel+duration then
        if not r.cashPrepared then
            local hash=model('prop_anim_cash_note')
            if stores[store.id]~=store or not store.state or store.state.activities['register:'..activity.point]~=activity then if hash then SetModelAsNoLongerNeeded(hash) end;return end
            r.cashPrepared=true
            if hash then
                r.cash=object(hash,r.origin,r.heading)
                if r.cash then
                    SetEntityVisible(r.cash,false,false)
                    AttachEntityToEntity(r.cash,ped,GetPedBoneIndex(ped,57005),0.1,0.02,0.0,0.0,0.0,90.0,false,false,false,true,2,true)
                end
            end
        end
        if r.stage~='emptying' then
            r.stage='emptying';ClearPedTasksImmediately(ped);FreezeEntityPosition(ped,false)
            -- Recréer une scène vivante : celle de présentation est figée à 0
            -- et peut déjà avoir été arrêtée par le moteur avant l'arrivée du ped.
            r.drawerScene=CreateSynchronizedScene(r.origin.x,r.origin.y,r.origin.z,0.0,0.0,r.heading,2)
            SetSynchronizedSceneHoldLastFrame(r.drawerScene,true)
            if not PlaySynchronizedEntityAnim(r.till,r.drawerScene,tillClip,dict,8.0,-8.0,0,0) then
                r.stage=nil
                if not r.warned then print('[cdt_marketrobbery_light] Échec du redémarrage du tiroir : '..activity.point);r.warned=true end
                return
            end
            SetEntityCoordsNoOffset(ped,start.x,start.y,start.z,false,false,false);SetEntityHeading(ped,rotation.z)
            TaskSynchronizedScene(ped,r.drawerScene,dict,pedClip,8.0,-8.0,-1,16,1.0,0)
            SetSynchronizedSceneRate(r.drawerScene,GetAnimDuration(dict,pedClip)/duration)
        end
        local phase=math.min(0.98,(elapsed-travel)/duration)
        setPhase(r,phase);ForceEntityAiAndAnimationUpdate(ped);renderCash(r,ped,phase)
        if phase>=R.dropPhase and not r.dropped then
            r.dropped=true
            if r.bag then
                local entity=r.bag;r.bag=nil
                DetachEntity(entity,true,true);SetEntityCollision(entity,true,true);SetEntityHasGravity(entity,true)
                FreezeEntityPosition(entity,false)
                SetEntityDynamic(entity,true);ActivatePhysics(entity)
                local p=GetEntityCoords(entity)
                local target=R.dropPosition(r.config)
                SetEntityVelocity(entity,(target.x-p.x)*0.8,(target.y-p.y)*0.8,-0.35)
                store.bags[activity.point]={entity=entity,fallingUntil=GetGameTimer()+1800,position=p}
            end
        end
        return
    end
    if r.cash then DeleteEntity(r.cash);r.cash=nil;r.cashInHand=nil end
    -- Après un saut temporel, le stock serveur reconstruit le sac au sol.
    if not r.dropped then r.dropped=true;if r.bag then DeleteEntity(r.bag);r.bag=nil end end
    SetSynchronizedSceneRate(r.drawerScene,0.0);setPhase(r,r.visual.openPhase)
    if r.stage~='returning' and r.stage~='giving' then
        r.stage='returning'
        if r.bag then carryBag(r.bag,ped,false) end
        walk(ped,store.home,store.home.heading,(travel+duration+travel-elapsed)*1000)
    end
end
local function groundBags(store)
    local stock=store.state and store.state.bags or {}
    for id,bag in pairs(store.bags) do
        if stock[id] and stock[id].status=='taken' or not stock[id] and (not bag.fallingUntil or GetGameTimer()>=bag.fallingUntil) then
            if bag.entity then DeleteEntity(bag.entity) end;store.bags[id]=nil
        end
    end
    for id,bag in pairs(stock) do if bag.status=='ready' then
        local visual=store.bags[id]
        -- Un observateur tardif reconstruit le sac directement au sol.
        local r=store.registers[id]
        if not visual and not (r and r.activity and not r.dropped) then
            local hash=model(bag.model or r and R.bagModel(r.config) or 'prop_poly_bag_01')
            if stores[store.id]~=store or not store.state.bags or store.state.bags[id]~=bag then if hash then SetModelAsNoLongerNeeded(hash) end;return end
            local entity=hash and object(hash,bag.position,bag.position.heading or 0)
            if entity then visual={entity=entity};store.bags[id]=visual end
        end
        if visual and not visual.settled and (not visual.fallingUntil or GetGameTimer()>=visual.fallingUntil) then
            SetEntityCollision(visual.entity,true,true)
            visual.settled=MarketGround.settle(visual.entity,bag.position,false)
        end
    end end
end
function M.points(id)
    local store=stores[id];local points={}
    for point,bag in pairs(store and store.state and store.state.bags or {}) do
        if bag.status=='ready' and GetGameTimer()/1000+timeOffset>=(bag.availableAt or 0) then
            local p=bag.position;points[#points+1]={id=point,x=p.x,y=p.y,z=p.z,label='Ramasser le sac de la caisse'}
        end
    end
    return points
end
CreateThread(function()
    while true do
        local animating=false;local now=GetGameTimer()/1000+timeOffset
        for _,store in pairs(stores) do
            local working=false
            for id,r in pairs(store.registers) do
                local state=store.state;local activity=state and state.activities and state.activities['register:'..id]
                if activity then
                    working=true;animating=true;renderActivity(store,r,activity,now)
                else
                    if r.activity then clearAccessories(r) end
                    SetSynchronizedSceneRate(r.drawerScene,0.0)
                    setPhase(r,state and state.registers[id]=='looted' and r.visual.openPhase or 0)
                end
            end
            if not working then restoreClerk(store) end
            groundBags(store)
        end
        Wait(animating and 0 or 200)
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then for id in pairs(stores) do M.remove(id) end end
end)
