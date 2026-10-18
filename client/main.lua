local data={config={stores={}},states={},revision=-1}
local Presentation=require 'shared.presentation'
local Locale=require 'shared.locale'
local Loot=require 'shared.loot'
local RegisterRules=require 'shared.registers'
local DebugMinigames=require 'client.debug_minigames'
local InventoryPresentation=require 'client.inventory'
local Notifications=require 'client.notifications'
local debugMinigame
local spawned,objects,zones={}, {}, {}
local active,ui,placing=nil,nil,false
local actionPending=false
local inventory
local editorPreview
local target='key'
local testimonyAvailable={}
local alertBlips={}
local alertLabels={}
local function nameAlert(blip,label)
    BeginTextCommandSetBlipName('STRING');AddTextComponentString(Locale.text('Braquage · '..label,Config.language));EndTextCommandSetBlipName(blip)
end
local function clearAlert(blip)
    local radius=alertBlips[blip];if not radius then return end
    alertBlips[blip]=nil;alertLabels[blip]=nil;RemoveBlip(blip);RemoveBlip(radius)
end
local function aimingAtClerk(id)
    local store
    for _, entry in ipairs(data.config.stores) do if entry.id==id then store=entry;break end end
    if type(store)~='table' then return false end
    local ped=spawned[id]
    if not ped or not DoesEntityExist(ped) or IsPauseMenuActive() or IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(),false) then return false end
    local rule=(((store.settings or {}).requirements or (data.config.defaults or {}).requirements or {}).intimidate or {})
    local selected=GetSelectedPedWeapon(PlayerPedId())
    local weapons=rule.weapons or {}
    -- Une liste vide signifie « aucune restriction d'arme », comme côté serveur.
    -- La scène d'intimidation nécessite néanmoins une arme effectivement équipée.
    local allowed=#weapons==0 and selected~=joaat('WEAPON_UNARMED')
    for _, weapon in ipairs(weapons) do if selected==joaat(weapon) then allowed=true;break end end
    local targeting=#(GetEntityCoords(PlayerPedId())-GetEntityCoords(ped))<=4.5
        and #(GetEntityCoords(PlayerPedId())-vector3(store.center.x,store.center.y,store.center.z))<=store.radius
        and IsPlayerFreeAimingAtEntity(PlayerId(),ped) and HasEntityClearLosToEntity(PlayerPedId(),ped,17)
    if not targeting then return false end
    if not allowed then return false,'weapon' end
    return true
end
local function watchingClerk(id)
    local ped=spawned[id]
    if not ped or not DoesEntityExist(ped) or IsPauseMenuActive() then return false end
    local p=GetEntityCoords(ped)
    local visible,x,y=GetScreenCoordFromWorldCoord(p.x,p.y,p.z+0.7)
    return visible and x>0 and x<1 and y>0 and y<1 and HasEntityClearLosToEntity(PlayerPedId(),ped,17)
end
local function notify(message,kind,duration,administrative)
    if not administrative then message=Presentation.notification(message)end
    return Notifications.send({message=message,type=kind,duration=duration,administrative=administrative})
end
RegisterNetEvent('cdt_market_light:notify',notify)
local function notifyLoot(received)
    local items=InventoryPresentation.prepare({chunks=received},data.config.inventoryType).chunks
    local summary={}
    for _,item in ipairs(items)do summary[#summary+1]=('%s × %s'):format(item.label or item.name,item.amount) end
    local message='Butin récupéré : '..table.concat(summary,', ')..'.'
    if #items>0 then Notifications.send({category='loot',items=items,message=message,type='success'}) end
    return message
end
local function safeDebug(event,detail)
    if not Config or Config.debug~=true then return end
    print('[cdt_marketrobbery_light][debug][client][coffre] '..event..' '..json.encode(detail or {}))
end
local function requestResult(name,...)
    local tracing=name=='safeInventory' or name=='begin' or name=='finish' or name=='safeStep'
    if tracing then safeDebug('request',{callback=name,store=inventory and inventory.store or active and active.store,point=inventory and inventory.point or active and active.point,revision=data.revision}) end
    local ok,result=pcall(lib.callback.await,'cdt_market_light:'..name,false,...)
    if tracing then safeDebug('response',{callback=name,transport=ok,error=not ok and tostring(result) or type(result)=='table' and result.error,ok=type(result)=='table' and result.ok,chunks=type(result)=='table' and result.chunks}) end
    if not ok or type(result)~='table' then return {error='Le serveur ne répond pas.'} end
    return result
end
local function request(name,...)
    local result=requestResult(name,...)
    if result.error then notify(result.error,'error',nil,name=='admin' or name=='reset' or name=='debugMinigame'); return nil end
    return result
end
local function pointDistance(p) return #(GetEntityCoords(PlayerPedId())-vector3(p.x,p.y,p.z)) end
local function storeById(id) for _, s in ipairs(data.config.stores) do if s.id==id then return s end end end
local function closeUI()
    if ui=='admin' then TriggerServerEvent('cdt_market_light:editorClosed')end
    debugMinigame=nil
    
    if inventory then safeDebug('inventory_closed',{store=inventory.store,point=inventory.point}) end
    inventory=nil
    ui=nil; placing=false;if editorPreview then DeleteEntity(editorPreview);editorPreview=nil end; SetNuiFocus(false,false); SendNUIMessage({type='close'})
end
local function cleanupStore(id)
    MarketRegisters.remove(id)
    MarketSafes.remove(id)
    if spawned[id] then MarketClerk.clear(spawned[id]); DeleteEntity(spawned[id]); spawned[id]=nil end
    for _, entity in ipairs(objects[id] or {}) do DeleteEntity(entity) end; objects[id]=nil
    for _, zone in ipairs(zones[id] or {}) do
        if target=='ox' and GetResourceState('ox_target')=='started' then exports.ox_target:removeZone(zone)
        elseif target=='qb' and GetResourceState('qb-target')=='started' then exports['qb-target']:RemoveZone(zone) end
    end
    zones[id]=nil
end
local runAction,receive
local function finishAction(success)
    local action=active; if not action then return end
    if action.stage=='register' then SendNUIMessage({type='clerkWatch',visible=false}) end
    if ui=='safe' then closeUI() end
    MarketRegisters.stopPlayer()
    if action.stage~='register' then ClearPedTasks(PlayerPedId()) end
    if action.stage=='safe' and success then MarketSafes.open(action.store,action.point,function()return active==action end) end
    if active~=action then return end
    local result
    if action.stage=='collect' then result=requestResult('finish',action.token,success==true)
    else result=request('finish',action.token,success==true) end
    if active~=action then return result end
    active=nil
    if result and result.sync then receive(result.sync) end
    if action.stage=='collect' and success~=true then return {error='Récupération annulée.'} end
    if action.stage=='collect' and result and result.error then
        result.error=Presentation.notification(result.error);notify(result.error,'error')
    elseif action.stage=='collect' and result and result.ok and result.received then
        result.message=notifyLoot(result.received)
    elseif result and result.message then notify(result.message,'success') end
    if result and result.next then runAction(action.store,result.next) end
    return result
end
local function openInventory(id,point)
    local result=request('safeInventory',id,point)
    if not result or active or ui or placing or IsEntityDead(PlayerPedId()) then return end
    local store=storeById(id);local state=data.states[id];local safe
    for _,entry in ipairs(store and store.safes or {}) do if entry.id==point then safe=entry;break end end
    if not safe or pointDistance(safe)>2.5 or not Loot.viewable(state,point) then safeDebug('inventory_open_blocked',{store=id,point=point,found=safe~=nil,distance=safe and pointDistance(safe),viewable=Loot.viewable(state,point)});return end
    safeDebug('inventory_opened',{store=id,point=point,chunks=result.chunks,canTake=result.canTake})
    inventory=result;ui='inventory';SetNuiFocus(true,true)
    SendNUIMessage({type='inventory',data=InventoryPresentation.prepare(result,data.config.inventoryType)})
end
local function interact(id,stage,point,chunk)
    if active or actionPending or ui or placing or lib.progressActive and lib.progressActive() or IsEntityDead(PlayerPedId()) then return end
    if stage=='bag' then local result=request('pickupBag',id,point);if result and result.message then notify(result.message,'success') end;return end
    if stage=='collect' then openInventory(id,point);return end
    actionPending=true
    local result=request('begin',id,stage,point,chunk)
    actionPending=false
    if not result then return end
    runAction(id,result)
end
runAction=function(id,result)
    local stage,point=result.stage,result.point
    active=result; active.store=id
    if stage=='intimidate' then
        local started=GetGameTimer()
        local duration=result.duration*1000
        local success=true
        while active==result do
            if ui or placing or not aimingAtClerk(id) then success=false;break end
            local elapsed=GetGameTimer()-started
            SendNUIMessage({type='intimidation',visible=true,elapsed=elapsed,duration=duration})
            if elapsed>=duration then break end
            Wait(0)
        end
        SendNUIMessage({type='intimidation',visible=false})
        if active==result then return finishAction(success) end
    elseif stage=='register' then
        local started=GetGameTimer()
        if not MarketRegisters.play(id,point,result.duration) then
            finishAction(false); notify('Le commerçant ne peut pas vider cette caisse pour le moment.','error'); return
        end
        local watchDuration=(result.watchDuration or result.duration)*1000
        local lostAt,lastWatched
        -- Surveillance visuelle, sans immobilisation ni cercle de progression.
        while active==result and GetGameTimer()-started<result.duration*1000 do
            if IsEntityDead(PlayerPedId()) then return finishAction(false) end
            local now=GetGameTimer()
            if now-started<watchDuration then
                local watched=not ui and not placing and watchingClerk(id)
                if watched~=lastWatched then SendNUIMessage({type='clerkWatch',visible=true,watched=watched});lastWatched=watched end
                if watched then lostAt=nil
                else
                    lostAt=lostAt or now
                    if now-lostAt>=1000 then
                        finishAction(false)
                        notify('Vous avez détourné le regard. Le commerçant a cessé de préparer le sac. Retournez le voir pour lui demander de reprendre la caisse.','warning',8000)
                        return
                    end
                end
            elseif lastWatched~=nil then SendNUIMessage({type='clerkWatch',visible=false});lastWatched=nil end
            Wait(0)
        end
        if active==result then return finishAction(not IsEntityDead(PlayerPedId())) end
    elseif stage=='safe' then
        ui='safe'; SetNuiFocus(true,true)
        SendNUIMessage({type='safe',data=result})
    else
        local options={duration=result.duration*1000,label=Locale.text(stage=='intimidate' and 'Intimidation du commerçant…' or stage=='collect' and 'Récupération du butin…' or 'Le commerçant vide la caisse et prépare le sac…',Config.language),canCancel=true,useWhileDead=false,disable={move=true,car=true,combat=true}}
        if stage=='collect' and not MarketSafes.play(id,point,function()return active and active.token==result.token end) then if active and active.token==result.token then finishAction(false);notify('Le coffre ou ses animations ne sont pas disponibles.','error') end;return end
        if not active or active.token~=result.token then MarketRegisters.stopPlayer(); return end
        local success
        if stage=='collect' then
            local reason
            success,reason=InventoryPresentation.progress(options.duration,function()return active==result and ui=='inventory' end)
            safeDebug('collection_progress',{token=result.token,success=success,reason=reason})
        else success=lib.progressCircle(options) end
        if active and active.token==result.token then return finishAction(success) end
    end
end
local function canInteract(id,stage,point,chunk)
    local state=data.states[id]; if not state or active or actionPending or ui or placing or lib.progressActive and lib.progressActive() or IsEntityDead(PlayerPedId()) then return false end
    if (stage=='testimony' or stage=='inspectRegister' or stage=='inspectSafe' or stage=='reopen') and state.phase~='active' and state.phase~='cooldown' and state.phase~='investigation' then return false end
    if not Presentation.robberyAllowed(Config,testimonyAvailable) then return false end
    if stage=='register' and MarketRegisters.ready and not MarketRegisters.ready(id,point) then return false end
    if stage=='bag' then return state.bags and state.bags[point] and state.bags[point].status=='ready' end
    if (stage=='safe' or stage=='collect') and not MarketSafes.ready(id,point) then return false end
    local now=(data.serverTime or 0)+(GetGameTimer()-(data.receivedAt or GetGameTimer()))/1000
    local store=storeById(id); local config
    for _, safe in ipairs(store.safes or {}) do if safe.id==point then config=safe; break end end
    return Presentation.available(state,stage,point,config,now,data.globalUntil,chunk)
end
local function addZone(store,point,stage,label)
    label=Locale.text(label,Config.language)
    zones[store.id]=zones[store.id] or {}
    local name='cdt_market_light_'..store.id..'_'..stage..'_'..(point.id or 'clerk')
    local id
    if target=='ox' then
        id=exports.ox_target:addSphereZone({coords=vector3(point.x,point.y,point.z),radius=0.65,debug=false,options={{name=name,label=label,icon='fa-solid fa-cash-register',distance=stage=='intimidate' and 4.5 or 2.5,canInteract=function() return canInteract(store.id,stage,point.id) end,onSelect=function() interact(store.id,stage,point.id) end}}})
    elseif target=='qb' then
        exports['qb-target']:AddCircleZone(name,vector3(point.x,point.y,point.z),0.65,{name=name,useZ=true},{options={{label=label,icon='fas fa-cash-register',canInteract=function() return canInteract(store.id,stage,point.id) end,action=function() interact(store.id,stage,point.id) end}},distance=stage=='intimidate' and 4.5 or 2.5})
        id=name
    end
    if id then zones[store.id][#zones[store.id]+1]=id end
end
local function modelHash(model)
    local hash=joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    local ok=pcall(lib.requestModel,hash,5000); return ok and hash or nil
end
local clerkRetryAt={}
local function spawnClerk(store)
    if spawned[store.id] or GetGameTimer()<(clerkRetryAt[store.id] or 0) then return end
    clerkRetryAt[store.id]=GetGameTimer()+5000
    local p=store.clerk; local hash=modelHash(p.model)
    if hash and IsModelAPed(hash) then
        local initial=p.placement and p or MarketGround.origin(hash,{x=p.x,y=p.y,z=p.z-1.0},p.heading)
        local ped=CreatePed(4,hash,initial.x,initial.y,initial.z,p.heading,false,false)
        SetEntityInvincible(ped,true); SetBlockingOfNonTemporaryEvents(ped,true)
        SetPedCanRagdoll(ped,false)
        if MarketGround.settle(ped,p,true) then spawned[store.id]=ped else DeleteEntity(ped);print('[cdt_marketrobbery_light] Commerçant sans appui au sol : '..store.id) end
        SetModelAsNoLongerNeeded(hash)
    end
end
local function spawnStore(store)
    spawnClerk(store)
    if objects[store.id] then
        MarketSafes.ensure(store);MarketRegisters.ensure(store);MarketRegisters.bind(store.id,spawned[store.id],store.clerk);return
    end
    objects[store.id]={}
    for _, prop in ipairs(store.props or {}) do
        local model=modelHash(prop.model)
        if model and not IsModelAPed(model) and not IsModelAVehicle(model) then
            local obj=CreateObjectNoOffset(model,prop.x,prop.y,prop.z,false,false,false)
            SetEntityHeading(obj,prop.heading); SetEntityInvincible(obj,true)
            if MarketGround.settle(obj,prop,false) then objects[store.id][#objects[store.id]+1]=obj else DeleteEntity(obj);print('[cdt_marketrobbery_light] Prop sans appui au sol : '..store.id) end; SetModelAsNoLongerNeeded(model)
        end
    end
    MarketSafes.ensure(store)
    MarketRegisters.ensure(store)
    MarketRegisters.bind(store.id,spawned[store.id],store.clerk)
    if target~='key' then
        addZone(store,store.clerk,'register','Demander au commerçant de vider les caisses')
        for _, safe in ipairs(store.safes or {}) do local p=safe.interaction;addZone(store,{id=safe.id,x=p.x,y=p.y,z=p.z},'safe','Ouvrir · '..safe.label);addZone(store,{id=safe.id,x=safe.x,y=safe.y,z=safe.z},'collect','Prendre le butin · '..safe.label) end
    end
end
local rebuild=false
local configured=false
local appliedLocalization
receive=function(snapshot)
    if type(snapshot)~='table' or not snapshot.revision or snapshot.revision<data.revision then return end
    -- Un événement partiel peut arriver avant la première réponse complète.
    -- Ne pas avancer la révision tant que la configuration initiale manque.
    if not snapshot.config and not configured then return end
    if snapshot.config then configured=true else snapshot.config=data.config end
    for key,value in pairs(snapshot.config.preferences or {})do
        if key=='localization' and type(value)=='table' and value~=appliedLocalization then
            appliedLocalization=value;Config.language=value.language;SendNUIMessage({type='localization',data=value})
            for blip,label in pairs(alertLabels)do nameAlert(blip,label)end
        end
        if key=='debug' or key=='target' or key=='notifications' or key=='notificationDuration' or key=='policeAlertRadius' or key=='policeAlertDuration' or key=='policeCanRob'then Config[key]=value end
    end
    local old=json.encode(data.config); data=snapshot; data.receivedAt=GetGameTimer()
    MarketRegisters.clock(snapshot.serverTime)
    MarketSafes.clock(snapshot.serverTime)
    for id,state in pairs(data.states) do MarketRegisters.sync(id,state);MarketSafes.sync(id,state);if spawned[id] then MarketClerk.update(spawned[id],state) end end
    if old~=json.encode(data.config) then rebuild=true end
    if ui=='admin' then SendNUIMessage({type='live',states=data.states,globalUntil=data.globalUntil,serverTime=data.serverTime}) end
    if ui=='inventory' and inventory then
        local state=data.states[inventory.store];local stock=state and state.safes[inventory.point]
        if not Loot.viewable(state,inventory.point) then closeUI()
        else inventory.chunks=stock.chunks or {};inventory.canTake=Loot.collectable(state,inventory.point);inventory.revision=data.revision;SendNUIMessage({type='inventoryLive',data=InventoryPresentation.prepare(inventory,data.config.inventoryType)}) end
    end
end
RegisterNetEvent('cdt_market_light:sync',receive)
local function refreshState()
    local ok,result=pcall(lib.callback.await,'cdt_market_light:sync',false,configured and data.revision or -1)
    if ok and type(result)=='table' and not result.error then
        if result.unchanged then
            MarketRegisters.clock(result.serverTime);MarketSafes.clock(result.serverTime)
            data.serverTime=result.serverTime;data.receivedAt=GetGameTimer()
        else receive(result) end
    end
end
local function resync()
    CreateThread(function() Wait(1000); refreshState() end)
end
RegisterNetEvent('QBCore:Client:OnPlayerLoaded',resync)
RegisterNetEvent('esx:playerLoaded',resync)
CreateThread(function()
    Wait(1500)
    while true do
        refreshState()
        Wait(configured and 30000 or 3000)
    end
end)
RegisterNetEvent('cdt_market_light:cancel',function()
    SendNUIMessage({type='clerkWatch',visible=false})
    testimonyAvailable={}
    if active then active=nil; MarketRegisters.stopPlayer(); if lib.progressActive() then lib.cancelProgress() end; ClearPedTasks(PlayerPedId()); if ui=='safe' then closeUI() end; notify('Action interrompue.','error') end
end)
RegisterNetEvent('cdt_market_light:alert',function(label,point)
    local duration=(Config.policeAlertDuration or 90)*1000
    Notifications.send({category='police',location=label,message=Locale.text('Braquage · '..label,Config.language),type='warning',duration=duration})
    local blip=AddBlipForCoord(point.x,point.y,point.z); SetBlipSprite(blip,161); SetBlipColour(blip,1); SetBlipScale(blip,1.1)
    SetBlipAsShortRange(blip,false)
    local radius=AddBlipForRadius(point.x,point.y,point.z,Config.policeAlertRadius or 50.0)
    SetBlipColour(radius,1);SetBlipAlpha(radius,150);SetBlipAsShortRange(radius,false)
    alertBlips[blip]=radius
    alertLabels[blip]=label;nameAlert(blip,label)
    CreateThread(function()
        local bright=true
        while alertBlips[blip]==radius do
            Wait(500)
            if alertBlips[blip]~=radius then break end
            bright=not bright;SetBlipAlpha(radius,bright and 150 or 30)
        end
    end)
    SetTimeout(duration,function()clearAlert(blip)end)
end)
RegisterCommand('marketlightadmin',function()
    if active or placing then return end
    local result=request('admin'); if not result then return end
    ui='admin'; SetNuiFocus(true,true); SendNUIMessage({type='admin',data=result})
end,false)
RegisterCommand('marketlightreset',function(_,args)
    if not args[1] then notify('Utilisation : /marketlightreset identifiant_magasin'); return end
    local answer=lib.alertDialog({header=Locale.text('Réinitialiser la supérette ?',Config.language),content=Locale.text('Les interactions en cours seront annulées. Le délai global sera conservé.',Config.language),labels={confirm=Locale.text('Confirmer',Config.language),cancel=Locale.text('Annuler',Config.language)},centered=true,cancel=true})
    if answer=='confirm' then local result=request('reset',args[1]); if result then notify(result.message,'success') end end
end,false)
RegisterCommand('marketlightminigame',function(_,args)
    if active or ui or placing or debugMinigame then return end
    local difficulty=args[1]=='dial' and (args[2] or 'normal') or (args[1] or 'normal')
    local result=request('debugMinigame','dial',difficulty)
    if not result or active or ui or placing then return end
    debugMinigame=DebugMinigames.start(result.game,GetGameTimer())
    local c=debugMinigame.challenge
    ui='debugMinigame';SetNuiFocus(true,true)
    SendNUIMessage({type='safe',data={game=result.game,duration=result.game.duration,steps=result.game.steps,tolerance=result.game.tolerance,target=c.target,phase=c.phase,direction=c.direction,label='Debug'}})
end,false)
RegisterNUICallback('close',function(_,cb)
    if ui=='safe' then finishAction(false) else
        if ui=='inventory' and active and active.stage=='collect' then
            if lib.progressActive() then lib.cancelProgress() end
            finishAction(false)
        end
        closeUI()
    end; cb({ok=true})
end)
RegisterNUICallback('inventoryTake',function(payload,respond)
    safeDebug('inventory_take',{store=inventory and inventory.store,point=inventory and inventory.point,chunk=type(payload)=='table' and payload.chunk,quantity=type(payload)=='table' and payload.quantity,all=type(payload)=='table' and payload.all})
    local function cb(result)
        safeDebug('inventory_take_result',{error=result.error,received=result.received,inventory=result.inventory})
        if result.error then result.error=Presentation.notification(result.error);notify(result.error,'error') end
        respond(result)
    end
    if ui~='inventory' or not inventory or active or type(payload)~='table' or type(payload.chunk)~='string' then cb({error='Récupération indisponible.'});return end
    local session=inventory
    if not Loot.collectable(data.states[session.store],session.point) then cb({error='Ce coffre est uniquement consultable.'});return end
    local result=requestResult('begin',session.store,'collect',session.point,payload.chunk,payload.quantity,nil,payload.all==true)
    if result.error then cb(result);return end
    if ui~='inventory' or inventory~=session then request('finish',result.token,false);cb({error='Inventaire fermé.'});return end
    local ok,outcome=xpcall(function()return runAction(session.store,result)end,debug.traceback)
    if not ok then
        print('[cdt_marketrobbery_light] inventoryTake : '..tostring(outcome))
        if active and active.token==result.token then finishAction(false) end
        cb({error='Récupération interrompue.'});return
    end
    if outcome and outcome.inventory then outcome.inventory=InventoryPresentation.prepare(outcome.inventory,data.config.inventoryType) end
    cb(outcome or {error='Récupération interrompue.'})
end)
CreateThread(function()
    while true do
        Wait(250)
        if ui=='debugMinigame' and IsEntityDead(PlayerPedId()) then closeUI() end
        if ui=='inventory' and inventory then
            local store=storeById(inventory.store);local point
            for _,s in ipairs(store and store.safes or {}) do if s.id==inventory.point then point=s;break end end
            if not point or pointDistance(point)>2.5 or IsEntityDead(PlayerPedId()) then
                closeUI()
                if active and active.stage=='collect' then if lib.progressActive() then lib.cancelProgress() end;finishAction(false) end
            end
        end
    end
end)
RegisterNUICallback('save',function(payload,cb)
    if type(payload.config)~='table' or type(payload.config.stores)~='table' then cb({error='Configuration invalide.'}); return end
    for _, store in ipairs(payload.config.stores) do
        for _,register in ipairs(store.registers or {}) do
            local valid,why=RegisterRules.validate(register)
            if not valid then cb({error=why});return end
            if register.bag then
                local model=joaat(register.bag.model)
                if not IsModelInCdimage(model) or not IsModelValid(model) or IsModelAPed(model) or IsModelAVehicle(model) then cb({error='Prop du sac invalide : '..register.bag.model});return end
            end
        end
        if type(store.clerk)~='table' or type(store.clerk.model)~='string' then cb({error='Modèle du commerçant manquant.'}); return end
        local hash=joaat(store.clerk.model)
        if not IsModelInCdimage(hash) or not IsModelAPed(hash) then cb({error='Modèle de commerçant invalide : '..store.clerk.model}); return end
        for _, prop in ipairs(store.props or {}) do
            if type(prop.model)~='string' then cb({error='Modèle de prop manquant.'}); return end
            local model=joaat(prop.model)
            if not IsModelInCdimage(model) or not IsModelValid(model) or IsModelAPed(model) or IsModelAVehicle(model) then cb({error='Modèle de prop invalide : '..prop.model}); return end
        end
        for _, safe in ipairs(store.safes or {}) do
            if safe.spawnProp then
                local model=joaat(safe.model)
                if not IsModelInCdimage(model) or not IsModelValid(model) or IsModelAPed(model) or IsModelAVehicle(model) then cb({error='Modèle de coffre GTA invalide : '..safe.model}); return end
            end
        end
    end
    local function validProps(list)
        for _,entry in ipairs(list or {}) do if entry.model then local hash=joaat(entry.model);if not IsModelInCdimage(hash) or not IsModelValid(hash) or IsModelAPed(hash) or IsModelAVehicle(hash) then return false,entry.model end end end
        return true
    end
    local valid,bad=validProps(payload.config.defaults.safeLoot)
    if not valid then cb({error='Prop de butin invalide : '..bad});return end
    for _,store in ipairs(payload.config.stores) do
        valid,bad=validProps(store.settings.safeLoot)
        if not valid then cb({error='Prop de butin invalide : '..bad});return end
        for _,safe in ipairs(store.safes or {}) do
            valid,bad=validProps(safe.loot)
            if not valid then cb({error='Prop de butin invalide : '..bad});return end
            if safe.visual then for _,key in ipairs({'bodyModel','doorModel'}) do if safe.visual[key] then valid,bad=validProps({{model=safe.visual[key]}});if not valid then cb({error='Modèle de coffre ouvrant invalide : '..bad});return end end end end
        end
    end
    local result=request('save',payload.config,payload.revision); cb(result or {error='Enregistrement refusé.'})
end)
RegisterNUICallback('reload',function(_,cb) cb(request('admin') or {error='Chargement refusé.'}) end)
RegisterNUICallback('backup',function(_,cb) cb(request('backup') or {error='Sauvegarde indisponible.'}) end)
RegisterNUICallback('reset',function(payload,cb) cb(request('reset',payload.id) or {error='Réinitialisation refusée.'}) end)
RegisterNUICallback('deleteStore',function(payload,cb)
    if ui~='admin' or type(payload)~='table' then cb({error='Administration fermée.'});return end
    cb(request('deleteStore',payload.id,payload.revision) or {error='Suppression refusée.'})
end)
RegisterNUICallback('statistics',function(_,cb) cb(request('statistics') or {error='Statistiques indisponibles.'}) end)
local teleporting=false
local teleportPed,teleportFrozen
RegisterNUICallback('teleportStore',function(payload,cb)
    if ui~='admin' or placing or active or teleporting or type(payload)~='table'then cb({error='Téléportation indisponible.'});return end
    local ped=PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped,false)then cb({error='Sors de ton véhicule et reste en vie pour te téléporter.'});return end
    teleporting=true
    local result=request('teleportStore',payload.id)
    if not result or ui~='admin' or ped~=PlayerPedId() or IsEntityDead(ped)then teleporting=false;cb({error='Téléportation refusée.'});return end
    local p=result.point
    local previous=GetEntityCoords(ped)
    local frozen=IsEntityPositionFrozen(ped)
    teleportPed,teleportFrozen=ped,frozen
    FreezeEntityPosition(ped,true)
    RequestCollisionAtCoord(p.x,p.y,p.z)
    SetEntityCoordsNoOffset(ped,p.x,p.y,p.z,false,false,false)
    local deadline=GetGameTimer()+5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer()<deadline do RequestCollisionAtCoord(p.x,p.y,p.z);Wait(0)end
    local loaded=HasCollisionLoadedAroundEntity(ped)
    if not loaded and DoesEntityExist(ped)then RequestCollisionAtCoord(previous.x,previous.y,previous.z);SetEntityCoordsNoOffset(ped,previous.x,previous.y,previous.z,false,false,false)end
    if DoesEntityExist(ped)then FreezeEntityPosition(ped,frozen)end
    teleportPed=nil
    teleporting=false
    cb(loaded and {ok=true,message='Téléporté à '..result.label..'.'} or {error='Le lieu n’a pas pu être chargé. Téléportation annulée.'})
end)
RegisterNUICallback('saveAdministration',function(payload,cb)
    if ui~='admin' or type(payload)~='table'then cb({error='Administration fermée.'});return end
    local ok,result=pcall(lib.callback.await,'cdt_market_light:saveAdministration',false,payload.settings,payload.revision)
    cb(ok and type(result)=='table' and result or {error='Enregistrement administratif indisponible.'})
end)
RegisterNUICallback('creationContext',function(_,cb)
    if ui~='admin' or placing then cb({error='Ouvre l’administration pour créer une supérette.'}); return end
    local context,why=MarketAdmin.context(); if not context then cb({error=why}); return end
    local result=request('newStoreId'); if not result then cb({error='Identifiant indisponible.'}); return end
    context.id=result.id; cb(context)
end)
RegisterNUICallback('scanInterior',function(payload,cb)
    if ui~='admin' or placing then cb({error='Détection indisponible.'}); return end
    local result,why=MarketRegisters.scanMapping(function()return MarketAdmin.scan(payload.center,payload.radius,payload.interiorHash)end)
    cb(result or {error=why})
end)
RegisterNUICallback('capture',function(payload,cb)
    if type(payload.model)=='string' then local result,why=MarketGround.capture(payload.model);cb(result or {error=why});return end
    local p=GetEntityCoords(PlayerPedId()); cb({x=math.floor(p.x*100)/100,y=math.floor(p.y*100)/100,z=math.floor(p.z*100)/100,heading=math.floor(GetEntityHeading(PlayerPedId())*100)/100})
end)
RegisterNUICallback('place',function(payload,cb)
    if ui~='admin' or placing then cb({error='Placement indisponible.'}); return end
    local zone=payload.mode=='zone' or type(payload.path)=='string' and payload.path:match('^stores%.%d+%.center$')~=nil
    placing=true; SetNuiFocus(false,false); SendNUIMessage({type='placing'})
    cb({ok=true})
    CreateThread(function()
        SendNUIMessage({type='placementHint',visible=true})
        local preview=MarketAdmin and MarketAdmin.preview(payload)
        editorPreview=preview
        if payload.preview and not preview then
            placing=false; SendNUIMessage({type='placementHint',visible=false}); SetNuiFocus(true,true)
            SendNUIMessage({type='placed',path=payload.path,cancelled=true}); notify('Modèle de prévisualisation indisponible.','error'); return
        end
        local heading=tonumber(payload.heading) or GetEntityHeading(PlayerPedId())
        local radius=math.max(3,math.min(80,tonumber(payload.radius) or 18))
        local probe,hitPoint,hitNormal,lastHit=nil,nil,nil,0
        local groundCheck,placedPoint
        local shownRadius
        while placing do
            Wait(0)
            DisableControlAction(0,191,true); DisableControlAction(0,201,true)
            DisableControlAction(0,199,true); DisableControlAction(0,200,true); DisableControlAction(0,202,true)
            if preview or zone then
                for _,control in ipairs({174,175,14,15,16,17,37,241,242}) do DisableControlAction(0,control,true) end
                if IsDisabledControlPressed(0,174) then heading=(heading-90*GetFrameTime())%360 end
                if IsDisabledControlPressed(0,175) then heading=(heading+90*GetFrameTime())%360 end
                if zone then
                    if IsDisabledControlJustReleased(0,15) or IsDisabledControlJustReleased(0,241) then radius=math.min(80,radius+0.5) end
                    if IsDisabledControlJustReleased(0,14) or IsDisabledControlJustReleased(0,242) then radius=math.max(3,radius-0.5) end
                end
            end
            if zone and shownRadius~=radius then
                shownRadius=radius;SendNUIMessage({type='placementHint',visible=true,radius=radius})
            end
            local camera=GetGameplayCamCoord(); local rotation=GetGameplayCamRot(2)
            local pitch,yaw=math.rad(rotation.x),math.rad(rotation.z)
            local direction=vector3(-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch))
            if probe then
                local status,hit,point,normal=GetShapeTestResult(probe)
                if status~=1 then
                    if status==2 and (hit==1 or hit==true) then hitPoint=point; hitNormal=normal; lastHit=GetGameTimer() else hitPoint=nil end
                    probe=nil
                end
            end
            if not probe then
                local destination=camera+direction*40.0
                probe=StartShapeTestLosProbe(camera.x,camera.y,camera.z,destination.x,destination.y,destination.z,17,PlayerPedId(),7)
            end
            local valid=hitPoint and GetGameTimer()-lastHit<250
            local surfaceValid=valid
            if preview and valid then local supported; supported,groundCheck,placedPoint=MarketGround.preview(preview,hitPoint,heading,hitNormal,groundCheck);valid=supported==true end
            if preview and not surfaceValid then FreezeEntityPosition(preview,false) end
            if surfaceValid then DrawMarker(28,hitPoint.x,hitPoint.y,hitPoint.z,0.0,0.0,0.0,0.0,0.0,0.0,0.08,0.08,0.08,valid and 34 or 239,valid and 219 or 100,valid and 128 or 68,210,false,false,2,false,nil,nil,false) end
            if valid and zone then
                DrawMarker(1,hitPoint.x,hitPoint.y,hitPoint.z+0.05,0.0,0.0,0.0,0.0,0.0,0.0,radius*2,radius*2,0.6,34,219,128,65,false,false,2,false,nil,nil,false)
                for i=0,63 do
                    local a,b=i*math.pi/32,(i+1)*math.pi/32
                    DrawLine(hitPoint.x+math.cos(a)*radius,hitPoint.y+math.sin(a)*radius,hitPoint.z+0.1,hitPoint.x+math.cos(b)*radius,hitPoint.y+math.sin(b)*radius,hitPoint.z+0.1,34,219,128,255)
                end
            end
            local cancel=IsDisabledControlJustReleased(0,200) or IsDisabledControlJustReleased(0,202)
            local confirm=IsDisabledControlJustReleased(0,191) or IsDisabledControlJustReleased(0,201)
            if confirm and not valid and preview then notify('Pose le modèle sur une surface plane, avec toute sa base en appui.','error') end
            if cancel or confirm and valid then
                local p=preview and placedPoint or hitPoint
                placing=false; SendNUIMessage({type='placementHint',visible=false})
                SetNuiFocus(true,true)
                SendNUIMessage({type='placed',path=payload.path,cancelled=cancel,point=not cancel and {x=p.x,y=p.y,z=p.z,placement=p.placement,heading=heading,radius=zone and radius or nil} or nil})
            end
        end
        if groundCheck then MarketGround.release(groundCheck) end
        if preview and editorPreview==preview then DeleteEntity(preview);editorPreview=nil end
    end)
end)
RegisterNUICallback('safeStep',function(payload,cb)
    if ui=='debugMinigame' and debugMinigame then
        local result=DebugMinigames.step(debugMinigame,payload,GetGameTimer())
        if result.error or result.solved then closeUI();notify(result.error or 'Réussi',result.error and 'error' or 'success') end
        cb(result);return
    end
    if not active or ui~='safe' then cb({error='Aucune tentative active.'}); return end
    local result=request('safeStep',active.token,payload)
    if not result then active=nil; closeUI(); cb({error='Tentative terminée.'}); return end
    if result.solved then finishAction(true) end
    cb(result)
end)
RegisterNUICallback('safeFail',function(_,cb) if ui=='debugMinigame' then closeUI() else finishAction(false) end; cb({ok=true}) end)
CreateThread(function()
    Wait(1500)
    target=Presentation.target(Config,GetResourceState)
    local promptSent=false; local lastPromptAt=0; local targetCheckedAt=0
    while true do
        local delay=600
        if GetGameTimer()-targetCheckedAt>=1000 then
            targetCheckedAt=GetGameTimer()
            local nextTarget=Presentation.target(Config,GetResourceState)
            if nextTarget~=target then
                for id in pairs(objects) do cleanupStore(id) end
                target=nextTarget; rebuild=true
            end
        end
        if rebuild then for id in pairs(objects) do cleanupStore(id) end; rebuild=false end
        local closest,closestDistance=nil,100
        local prompts={}
        for _, store in ipairs(data.config.stores) do
            local distance=pointDistance(store.center)
            local streamRadius=Presentation.streamRadius(store)
            if store.enabled and distance<streamRadius then
                spawnStore(store)
                local ped=spawned[store.id]; local state=data.states[store.id]
                MarketRegisters.sync(store.id,state)
                MarketSafes.sync(store.id,state)
                if ped then MarketClerk.update(ped,state) end
                if not IsPauseMenuActive() then
                    local function consider(point,stage,label)
                        local d=pointDistance(point)
                        if d<(stage=='reopen' and 2.0 or stage=='intimidate' and 4.5 or 2.5) and canInteract(store.id,stage,point.id,point.chunk) and distance<=store.radius then
                            local visible,x,y=GetScreenCoordFromWorldCoord(point.x,point.y,point.z+0.28)
                            x,y=Presentation.promptPosition(visible,x,y)
                            do
                                local prompt={id=store.id..':'..stage..':'..(point.id or 'clerk')..(point.chunk and ':'..point.chunk or ''),store=store.id,stage=stage,point=point.id,chunk=point.chunk,label=label,x=x,y=y,distance=d,key=(stage=='reopen' or stage=='inspectRegister' or stage=='inspectSafe' or stage=='testimony' or stage=='bag' or target=='key') and 'E' or Config.targetKeyLabel or 'ALT'}
                                prompts[#prompts+1]=prompt
                                if d<closestDistance then closest=prompt; closestDistance=d end
                            end
                        end
                    end
                    consider(store.clerk,'register',state and state.pausedRegister and 'Demander au commerçant de reprendre la caisse' or 'Demander au commerçant de vider les caisses')
                    consider(store.clerk,'testimony','Recueillir le témoignage')
                    for _,point in ipairs(store.registers) do consider(point,'inspectRegister','Inspecter la caisse') end
                    if canInteract(store.id,'reopen') then
                        delay=0
                        local p=store.center
                        DrawMarker(1,p.x,p.y,p.z-0.95,0.0,0.0,0.0,0.0,0.0,0.0,4.0,4.0,0.06,34,219,128,55,false,false,2,false,nil,nil,false)
                        consider(store.center,'reopen','Réouvrir la supérette')
                    end
                    for _,point in ipairs(MarketRegisters.points(store.id)) do consider(point,'bag',point.label) end
                    for _, safe in ipairs(store.safes or {}) do
                        local p=safe.interaction;local point={id=safe.id,x=p.x,y=p.y,z=p.z}
                        -- Information partagée, même si le joueur ne peut pas interagir.
                        local stock=state and state.safes and state.safes[safe.id]
                        local now=(data.serverTime or 0)+(GetGameTimer()-(data.receivedAt or GetGameTimer()))/1000
                        local remaining=stock and math.max(0,math.ceil((stock.retryAt or 0)-now)) or 0
                        local blocked=stock and safe.attemptLimit and stock.failures>=safe.attemptLimit
                        if state and state.phase=='active' and stock and stock.status=='ready' and (remaining>0 or blocked) and pointDistance(point)<2.5 then
                            local visible,x,y=GetScreenCoordFromWorldCoord(p.x,p.y,p.z+0.28)
                            x,y=Presentation.promptPosition(visible,x,y)
                            prompts[#prompts+1]={id=store.id..':safeWait:'..safe.id,stage='safe',label=blocked and (safe.label..' · Serrure bloquée') or (safe.label..' · Mécanisme grippé · '..remaining..' s'),x=x,y=y,distance=pointDistance(point),disabled=true}
                        end
                        consider(point,'safe','Ouvrir · '..safe.label)
                        consider(point,'inspectSafe','Inspecter · '..safe.label)
                    end
                    for _,point in ipairs(MarketSafes.points(store.id)) do consider(point,'collect',point.label) end
                end
                if delay~=0 then delay=200 end
            elseif distance>streamRadius+20 and objects[store.id] then cleanupStore(store.id) end
        end
        if #prompts>0 then
            delay=0
            if GetGameTimer()-lastPromptAt>=33 then
                table.sort(prompts,function(a,b)return a.distance<b.distance end)
                while #prompts>6 do table.remove(prompts) end
                if closest then closest.selected=true end
                SendNUIMessage({type='prompts',points=prompts}); promptSent=true; lastPromptAt=GetGameTimer()
            end
            if closest and (target=='key' or closest.stage=='bag' or closest.stage=='testimony' or closest.stage=='inspectSafe' or closest.stage=='inspectRegister' or closest.stage=='reopen') and IsControlJustReleased(0,38) then
                local selected=closest; SendNUIMessage({type='prompts',points={}}); promptSent=false
                interact(selected.store,selected.stage,selected.point,selected.chunk)
            end
        elseif promptSent then SendNUIMessage({type='prompts',points={}}); promptSent=false end
        Wait(delay)
    end
end)
-- Surveillance indépendante des interactions clavier et des systèmes de cible.
CreateThread(function()
    local blockedNotice,noticeAt=nil,0
    while true do
        local delay=100
        if not active and not ui and not placing then
            for _, store in ipairs(data.config.stores) do
                local aiming,aimReason=aimingAtClerk(store.id)
                if store.enabled and (aiming or aimReason=='weapon') then
                    if aiming and canInteract(store.id,'intimidate') then
                        blockedNotice=nil
                        interact(store.id,'intimidate')
                    else
                        local state=data.states[store.id]
                        local now=(data.serverTime or 0)+(GetGameTimer()-(data.receivedAt or GetGameTimer()))/1000
                        local reason,message
                        if aimReason=='weapon' then
                            reason='weapon';message='Équipe une arme autorisée.'
                        elseif state and state.phase=='cooldown' then
                            reason='cooldown';message=('Le commerçant refuse de coopérer pour le moment. Revenez dans %s s.'):format(math.max(0,math.ceil((state.cooldownUntil or now)-now)))
                        elseif state and state.phase=='available' and now<(data.globalUntil or 0) then
                            reason='global';message=('Faites-vous oublier encore %s s avant de tenter un autre braquage.'):format(math.ceil(data.globalUntil-now))
                        elseif not Presentation.robberyAllowed(Config,testimonyAvailable) then
                            reason='job';message='Votre métier ne permet pas de participer à un braquage.'
                        elseif state and state.phase=='active' then
                            reason='active';message='Le commerçant coopère déjà. Demande-lui de vider les caisses.'
                        elseif state and (state.phase=='investigation' or state.phase=='reopening') then
                            reason='police';message='Cette supérette est en cours de réouverture après une intervention police.'
                        end
                        local key=store.id..':'..tostring(reason)
                        if message and (key~=blockedNotice or GetGameTimer()-noticeAt>=10000) then
                            notify(message,'inform');blockedNotice=key;noticeAt=GetGameTimer()
                        end
                    end
                    break
                end
            end
        end
        Wait(delay)
    end
end)
AddEventHandler('onResourceStop',function(r)
    if r~=GetCurrentResourceName() then return end
    SendNUIMessage({type='dispatchClear'})
    SendNUIMessage({type='clerkWatch',visible=false})
    if teleportPed and DoesEntityExist(teleportPed)then FreezeEntityPosition(teleportPed,teleportFrozen)end
    for blip in pairs(alertBlips) do clearAlert(blip) end
    placing=false;if editorPreview then DeleteEntity(editorPreview);editorPreview=nil end; SetNuiFocus(false,false)
    SendNUIMessage({type='intimidation',visible=false})
    SendNUIMessage({type='prompts',points={}}); SendNUIMessage({type='placementHint',visible=false})
    if lib.progressActive() then lib.cancelProgress() end
    for id in pairs(objects) do cleanupStore(id) end
end)
CreateThread(function()
    while true do
        local nearby=false
        for _,store in ipairs(data.config.stores) do
            if store.enabled and pointDistance(store.center)<=store.radius then nearby=true;break end
        end
        if nearby then
            local ok,result=pcall(lib.callback.await,'cdt_market_light:robberyAccess',false)
            testimonyAvailable=ok and type(result)=='table' and result or {}
        else testimonyAvailable={} end
        if Config.policeCanRob==false and testimonyAvailable.canRob==false then
            if active then
                if lib.progressActive() then lib.cancelProgress() end
                finishAction(false)
            end
            if ui=='inventory' then closeUI() end
        end
        Wait(1000)
    end
end)


RegisterNUICallback('modulesStatus',function(_,cb)cb(requestResult('modulesStatus'))end)
RegisterNUICallback('applyModules',function(_,cb)
 if ui~='admin'then cb({error='Ouvrez la configuration avant d’activer le module.'});return end
 cb(requestResult('applyModules'))
end)
