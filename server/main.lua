local D=require 'shared.domain'
local Registers=require 'shared.registers'
local S=require 'shared.safes'
local Loot=require 'shared.loot'
local robberySessions={}
local B=require 'server.bridge'
local RequiredInventory=require('server.requirement_inventory').new(B)
local Administration=require 'server.administration'
local Light=require 'server.light'
local Locale=require 'shared.locale'
local administrationRevision=0
local Stats=require 'server.statistics'
local statistics={}
local resource=GetCurrentResourceName()
local config=S.migrate({defaults=D.copy(Config.defaults),stores=D.copy(Config.stores)})
local states,actions,limits,busy={}, {}, {}, {}
local revision,globalUntil,sequence,configRevision=0,0,0,0
local moduleManager
local function safeDebug(event,detail)
    if not Config or Config.debug~=true then return end
    print('[cdt_marketrobbery_light][debug][server][coffre] '..event..' '..json.encode(detail or {}))
end
local ready=false
local Storage=require 'server.storage'
local read,write=Storage.read,Storage.write
local operating=false
local function persist()
    local ok=Storage.writeMany({state={states=states,globalUntil=globalUntil},statistics=statistics})
    if not ok then ready=false; print('[cdt_marketrobbery_light] Écriture impossible : ressource verrouillée pour protéger les paiements.') end
    return ok
end
local function storeById(id) for _, s in ipairs(config.stores) do if s.id==id then return s end end end
local function notify(src,msg,kind) TriggerClientEvent('cdt_market_light:notify',src,msg,kind or 'inform') end
local function audit(kind,src,id,detail)
    local entry={time=os.time(),kind=kind,player=src,name=src and GetPlayerName(src),store=id,detail=detail}
    print('[cdt_marketrobbery_light] '..json.encode(entry))
    if Config.webhook and Config.webhook~='' then PerformHttpRequest(Config.webhook,function() end,'POST',json.encode({content=json.encode(entry),allowed_mentions={parse={}}}),{['Content-Type']='application/json'}) end
end
local function publicConfig()
    local stores=D.copy(config.stores)
    for _, s in ipairs(stores) do
        local settings=D.settings(config,s)
        s.settings={requirements={intimidate={weapons=D.copy(settings.requirements.intimidate.weapons)}}}
        for index, safe in ipairs(s.safes) do
            safe=S.effective(safe,settings); s.safes[index]=safe
            safe.attemptLimit=S.resolve(safe.minigame).attempts; safe.loot=nil; safe.minigame=nil; safe.itemRequirements=nil; safe.inherit=nil
        end
        for _, r in ipairs(s.registers) do r.reward=nil; r.duration=nil end
    end
    return {stores=stores,inventoryType=B.inventory,preferences=Administration.preferences(Config)}
end
local function snapshot() return {config=publicConfig(),states=states,globalUntil=globalUntil,revision=revision,serverTime=os.time()} end
local function broadcast(id,configChanged)
    if id and states[id] then states[id].revision=(states[id].revision or 0)+1 end
    revision=revision+1
    local update={states=states,globalUntil=globalUntil,revision=revision,serverTime=os.time()}
    if configChanged then update.config=publicConfig() end
    TriggerClientEvent('cdt_market_light:sync',-1,update)
end
local function near(src,store,point,distance)
    local ped=GetPlayerPed(src); if not ped or ped==0 or GetEntityHealth(ped)<=0 or GetPlayerRoutingBucket(src)~=0 then return false end
    local p=GetEntityCoords(ped)
    return D.distance(p,store.center)<=store.radius and (not point or D.distance(p,point)<=(distance or 2.5))
end
local function checkRule(src,settings,stage)
    local ped=GetPlayerPed(src)
    return D.requirements(settings.requirements[stage],function(w) return B.weapon(src,w) end,function(w) return GetSelectedPedWeapon(ped)==joaat(w) end,function(i) return B.count(src,i) end,function(row)return RequiredInventory.count(src,row)end)
end
local function consume(src,items,when)
    local removed={}
    for _, i in ipairs(items) do
        if i.consume==when then
            local ok,taken,receipt=pcall(RequiredInventory.take,src,i)
            if not ok or not taken then
                for index=#removed,1,-1 do local old=removed[index];local restored,value=pcall(RequiredInventory.restore,src,old);if not restored or not value then audit('refund_failed',src,nil,old)end end
                return false
            end
            removed[#removed+1]=receipt
        end
    end
    return true
end
local function activityKey(a) return a.activityKey or a.stage..':'..(a.point or 'clerk') end
local function dropRegister(a)
    if a.stage~='register' or a.dropped or os.time()<a.dropAt then return false end
    local state=states[a.store]
    state.bags=state.bags or {}
    if state.bags[a.point] then return false end
    local rule=D.copy(a.settings.requirements.register);rule.items={};rule.itemMode='all'
    for _,item in ipairs(a.items) do if item.consume~='start' then rule.items[#rule.items+1]=item end end
    local valid=D.requirements(rule,function(w)return B.weapon(a.player,w)end,function(w)return GetSelectedPedWeapon(GetPlayerPed(a.player))==joaat(w)end,function(i)return B.count(a.player,i)end,function(row)return RequiredInventory.count(a.player,row)end)
    if not valid then return false end
    if not consume(a.player,a.items,'success') then return false end
    local reward=a.registerReward
    local session=Stats.current(statistics,a.store)
    state.bags[a.point]={status='ready',model=a.bagModel,position=a.dropPosition,droppedAt=a.dropAt,availableAt=a.dropAt+1.8,
        session=session and session.id,
        reward={kind=reward.kind,name=reward.name,amount=math.random(reward.min,reward.max)}}
    state.registers[a.point]='looted';a.dropped=true
    persist();broadcast(a.store)
    return true
end
local function finishStore(id,reason)
    local s=storeById(id); local state=states[id]; local settings=D.settings(config,s)
    Stats.finish(statistics,id,reason,os.time())
    state.phase='cooldown'; state.cooldownUntil=os.time()+settings.cooldown
    state.clerkCalm=true;state.clerkFrightened=false
    state.endsAt=nil; state.lastPresence=nil
    for src,a in pairs(actions) do if a.store==id then
        if a.stage=='register' and state.registers[a.point]=='busy' then state.registers[a.point]='ready' end
        if a.stage=='safe' and state.safes[a.point].status=='busy' then state.safes[a.point].status='ready' end
        if a.stage=='collect' then local chunk=Loot.find(state.safes[a.point],a.chunk);if chunk and chunk.status=='reserved' then chunk.status='ready' end end
        actions[src]=nil; TriggerClientEvent('cdt_market_light:cancel',src)
    end end
    state.activities={}
    persist(); broadcast(id); audit(reason,nil,id)
end
local function resetScene(id,reason)
    for src,a in pairs(actions) do
        if a.store==id then actions[src]=nil;TriggerClientEvent('cdt_market_light:cancel',src) end
    end
    Stats.finish(statistics,id,reason,os.time())
    states[id]=D.state(storeById(id))
    if not persist() then return false end
    broadcast(id)
    return true
end
local function expireScenes()
    for id,state in pairs(states) do
        if (state.phase=='cooldown' or state.phase=='investigation' or state.phase=='reopening') and state.cooldownUntil and os.time()>=state.cooldownUntil then
            resetScene(id,'reset_deadline')
        end
    end
end
local function release(src,failed,reason)
    local a=actions[src]; if not a then return end
    safeDebug('release',{player=src,store=a.store,point=a.point,stage=a.stage,chunk=a.chunk,failed=failed,reason=reason})
    local state=states[a.store]
    if state then
        if state.activities then state.activities[activityKey(a)]=nil end
        if a.stage=='intimidate' and state.phase=='intimidating' then state.phase='available';state.clerkFrightened=false; Stats.finish(statistics,a.store,reason or (failed and 'intimidation_failed' or 'intimidation_cancelled'),os.time())
        elseif a.stage=='register' and state.registers[a.point]=='busy' then state.registers[a.point]='ready';state.pausedRegister=a.point
        elseif a.stage=='collect' then
            local chunk=Loot.find(state.safes[a.point],a.chunk);if chunk and chunk.status=='reserved' then chunk.status='ready' end
        elseif a.stage=='safe' and state.safes[a.point].status=='busy' then
            local safeState=state.safes[a.point]; safeState.status='ready'
            if failed then
                safeState.failures=safeState.failures+1; safeState.retryAt=os.time()+a.game.penalty
                local message='Le mécanisme vous échappe. La serrure reste fermée.'
                if safeState.failures>=a.game.attempts then message='Vous avez trop forcé sur le mécanisme. La serrure est bloquée pour le reste du braquage.'
                elseif a.game.penalty>0 then message=('La serrure s’est grippée. Laissez le mécanisme se détendre pendant %s s avant de réessayer.'):format(a.game.penalty) end
                notify(src,message,'error')
            end
        end
    end
    actions[src]=nil
    if failed and not consume(src,a.items,'failure') then audit('failure_consumption_failed',src,a.store) end
    persist(); broadcast(a.store)
end
local function callback(name,handler)
    lib.callback.register('cdt_market_light:'..name,function(src,...)
        local first,second,third,fourth,fifth=...
        local action=actions[src]
        local tracing=name=='safeInventory' or name=='begin' and (second=='safe' or second=='collect') or (name=='finish' or name=='safeStep') and action and (action.stage=='safe' or action.stage=='collect')
        local context=tracing and {player=src,callback=name,store=action and action.store or first,point=action and action.point or (name=='begin' and third or second),stage=action and action.stage or (name=='begin' and second),chunk=action and action.chunk or (name=='begin' and fourth),quantity=name=='begin' and fifth,inventory=B.inventory,revision=revision} or nil
        local function respond(result)
            if tracing then
                context.error=result and result.error;context.ok=result and result.ok;context.canTake=result and result.canTake
                context.chunks=result and (result.chunks or result.inventory and result.inventory.chunks)
                context.received=result and result.received
                safeDebug('response',context)
            end
            return result
        end
        if tracing then safeDebug('request',context) end
        if not ready then return respond({error='Ressource indisponible. Consulter la console serveur.'}) end
        local key=src..':'..name; local now=GetGameTimer()
        if limits[key] and now-limits[key]<350 then return respond({error='Patiente un instant.'}) end; limits[key]=now
        if busy[src] then return respond({error='Une demande est déjà en cours.'}) end
        busy[src]=true
        -- Une fin d'action doit attendre le commit en cours, jamais être perdue.
        while operating do Wait(0) end
        if not ready then busy[src]=nil; return {error='Ressource indisponible. Consulter la console serveur.'} end
        operating=true
        local args=table.pack(...)
        local ok,result=xpcall(function()
            expireScenes()
            if not ready then return {error='Sauvegarde indisponible. Ressource verrouillée.'} end
            if moduleManager and moduleManager.reloading then return {error='Activation du module en cours. Patientez un instant.'}end
            return handler(src,table.unpack(args,1,args.n))
        end,debug.traceback)
        busy[src]=nil
        if not ok then
            print('[cdt_marketrobbery_light] '..result)
            pcall(release,src,false); operating=false; TriggerClientEvent('cdt_market_light:cancel',src)
            return respond({error='Erreur interne ; consulter la console serveur.'})
        end
        operating=false
        return respond(result)
    end)
end
moduleManager=require('server.modules').new({
 callback=callback,admin=B.admin,notify=notify,
 active=function()
  if next(actions)then return true end
  for _,state in pairs(states)do if state.phase=='active' or state.phase=='intimidating' or state.phase=='investigation' or state.phase=='reopening'then return true end end
  return false
 end
})
callback('robberyAccess',function(src)return {canRob=B.canRob(src)}end)
callback('snapshot',function() return snapshot() end)
-- Contrôle léger : le contenu complet ne repart que si le client a du retard.
callback('sync',function(_,knownRevision)
    if knownRevision==revision then return {unchanged=true,revision=revision,serverTime=os.time()} end
    return snapshot()
end)
callback('safeInventory',function(src,id,pointId)
    if type(id)~='string' or type(pointId)~='string' then return {error='Coffre invalide.'} end
    if not B.canRob(src) then return {error='Votre métier ne permet pas de participer à un braquage.'} end
    local store=storeById(id);local state=states[id]
    if not store or not store.enabled or not Loot.viewable(state,pointId) then return {error='Coffre indisponible.'} end
    local point
    for _,safe in ipairs(store.safes) do if safe.id==pointId then point=safe;break end end
    local stock=point and state.safes[pointId]
    if not stock or not stock.openedAt or (stock.status~='open' and stock.status~='looted') or not near(src,store,point) then return {error='Rapproche-toi du coffre ouvert.'} end
    return {store=id,point=pointId,label=point.label,chunks=D.copy(stock.chunks or {}),canTake=Loot.collectable(state,pointId),revision=revision}
end)
local registerChain={}
local function beginAction(src,id,stage,pointId,chunkId,quantity,chainKey,bestEffort)
    if type(id)~='string' or not ({intimidate=true,register=true,safe=true,collect=true})[stage] then return {error='Action invalide.'} end
    if not B.canRob(src) then return {error='Votre métier ne permet pas de participer à un braquage.'} end
    local store=storeById(id); if not store or not store.enabled then return {error='Magasin indisponible.'} end
    if actions[src] then return {error='Action déjà en cours.'} end
    local state=states[id]; local settings=D.settings(config,store); local point,safeConfig,game
    local autoRegisters=stage=='register' and pointId==nil
    if autoRegisters then
        if state.pausedRegister and state.registers[state.pausedRegister]=='ready' then pointId=state.pausedRegister
        else for _,register in ipairs(store.registers) do if state.registers[register.id]=='ready' then pointId=register.id;break end end end
    end
    if stage=='intimidate' then
        if state.phase~='available' then return {error='Ce magasin est occupé ou en recharge.'} end
        if os.time()<globalUntil then return {error='Délai global de braquage actif.'} end
        local active=0; for _, st in pairs(states) do if st.phase=='active' or st.phase=='intimidating' then active=active+1 end end
        if active>=settings.maxActive then return {error='Trop de braquages simultanés.'} end
        if B.policeCount()<settings.minPolice then return {error='Pas assez de policiers en service.'} end
        point=store.clerk
    else
        if state.phase~='active' then return {error='Le commerçant doit être braqué en premier.'} end
        if stage=='register' then
            for _,activity in pairs(state.activities or {}) do if activity.stage=='register' then return {error='Le commerçant vide déjà une autre caisse.'} end end
            for _, p in ipairs(store.registers) do if p.id==pointId then point=p end end
            if not point or state.registers[pointId]~='ready' then return {error='Caisse occupée ou déjà vidée.'} end
        else
            for _, s in ipairs(store.safes) do if s.id==pointId then safeConfig=S.effective(s,settings); point=s.interaction end end
            local safeState=safeConfig and state.safes[safeConfig.id]
            if stage=='collect' then
                point={x=safeConfig and safeConfig.x,y=safeConfig and safeConfig.y,z=safeConfig and safeConfig.z}
                local chunk=safeState and Loot.find(safeState,chunkId)
                if not safeState or safeState.status~='open' then return {error='Ce lot est indisponible.'} end
                if not chunk or chunk.status~='ready' then return {error='Ce lot est indisponible.',continue=true} end
            else
            if not safeState or safeState.status~='ready' or safeState.retryAt>os.time() then return {error='Coffre indisponible pour le moment.'} end
            game=S.resolve(safeConfig.minigame)
            if safeState.failures>=game.attempts then return {error='Nombre de tentatives épuisé pour ce coffre.'} end
            if safeConfig.requiresRegisters and not D.allRegisters(state) then return {error='Vide les caisses avant ce coffre.'} end
            end
        end
    end
    if stage~='collect' and safeConfig and safeConfig.itemRequirements then
        settings.requirements.safe.items=D.copy(safeConfig.itemRequirements.items)
        settings.requirements.safe.itemMode=safeConfig.itemRequirements.mode=='any' and 'any' or 'all'
    end
    local continuingRegisters=stage=='register' and chainKey==registerChain
    if continuingRegisters then
        if not near(src,store) then return {error='Rapproche-toi du point.'} end
    elseif not near(src,store,stage=='register' and store.clerk or point,stage=='intimidate' and 5.0 or 2.5) then return {error='Rapproche-toi du point.'} end
    local ok,items=true,{}
    if stage~='collect' then ok,items=checkRule(src,settings,stage) end; if not ok then return {error=items} end
    sequence=sequence+1
    local duration=stage=='intimidate' and settings.intimidateDuration or stage=='register' and (point.duration or settings.registerDuration) or stage=='collect' and (Config.lootGrabDuration or 3) or game.duration
    local animationDuration=stage=='register' and duration or nil
    local travelDuration=stage=='register' and math.max(1,math.ceil(D.distance(store.clerk,point)/1.5)+1) or nil
    if travelDuration then duration=duration+travelDuration*2+2 end
    local a={token=('%s:%s:%s'):format(os.time(),src,sequence),store=id,stage=stage,point=pointId,position=stage=='register' and store.clerk or point,started=os.time(),expires=os.time()+duration+15,settings=D.copy(settings),items=items,step=1,stepTime=GetGameTimer(),direction=1}
    a.duration=duration; a.game=game;a.autoRegisters=autoRegisters;a.registerReward=stage=='register' and D.copy(point.reward or settings.registerReward) or nil;
    if stage=='register' then
        -- Le joueur reste libre dans le magasin pendant le travail du commerçant.
        a.position=nil
        a.player=src;a.dropAt=a.started+travelDuration+animationDuration*Registers.dropPhase
        a.dropPosition=Registers.dropPosition(point)
        a.bagModel=Registers.bagModel(point)
    end
    if stage=='collect' then a.chunk=chunkId;a.activityKey='collect:'..pointId..':'..chunkId;a.reward=D.copy(Loot.find(state.safes[pointId],chunkId));a.bestEffort=bestEffort==true end
    if stage=='collect' and quantity~=nil then
        if type(quantity)~='number' or quantity%1~=0 or quantity<1 or quantity>a.reward.amount then return {error='Quantité invalide.'} end
        a.reward.amount=quantity
    end
 a.safeConfig=safeConfig and D.copy(safeConfig)
    actions[src]=a -- Réservation avant tout appel externe susceptible de suspendre l'exécution.
    if stage=='intimidate' then state.phase='intimidating';state.clerkFrightened=true;state.clerkCalm=nil elseif stage=='register' then state.registers[pointId]='busy';if state.pausedRegister==pointId then state.pausedRegister=nil end elseif stage=='collect' then Loot.find(state.safes[pointId],chunkId).status='reserved' else state.safes[pointId].status='busy' end
    state.activities=state.activities or {}
    state.activities[activityKey(a)]={stage=stage,point=pointId,chunk=chunkId,player=src,startedAt=a.started,duration=duration,animationDuration=animationDuration,travelDuration=travelDuration}
    if not consume(src,items,'start') then release(src,false); return {error='Impossible de consommer les objets.'} end
    if stage=='intimidate' then robberySessions[id]={participants={[tostring(src)]=true}}; Stats.start(statistics,id,a.token,os.time()) end
    if robberySessions[id] and stage~='intimidate' then robberySessions[id].participants=robberySessions[id].participants or {};robberySessions[id].participants[tostring(src)]=true end
    if stage=='safe' then state.safes[pointId].method=game.type end
    if not persist() then return {error='Échec de sauvegarde. Ressource verrouillée.'} end
    if stage=='safe' then
        a.challenge=S.challenge(game)
        state.activities['safe:'..pointId].step=1; state.activities['safe:'..pointId].steps=game.steps
    end
    broadcast(id)
    local result={token=a.token,duration=duration,stage=stage,point=pointId,animationDuration=animationDuration,watchDuration=stage=='register' and travelDuration+animationDuration*Registers.dropPhase or nil}
    if game then
        result.game=game; result.target=a.challenge.target; result.phase=a.challenge.phase; result.direction=a.challenge.direction
        result.steps=game.steps; result.tolerance=game.tolerance; result.label=safeConfig.label
    end
    return result
end
callback('begin',beginAction)
callback('safeStep',function(src,token,input,legacyDirection)
    local a=actions[src]
    if not a or a.stage~='safe' or a.token~=token then return {error='Tentative expirée.'} end
    if not B.canRob(src) then release(src,false);return {error='Votre métier ne permet pas de participer à un braquage.'} end
    local store=storeById(a.store)
    if os.time()>a.expires-15 or not near(src,store,a.position) then release(src,true); return {error='Tentative interrompue.'} end
    if type(input)=='number' then input={angle=input,direction=legacyDirection} end
    if type(input)~='table' then release(src,true); return {error='Entrée invalide.'} end
    local c=a.challenge; local elapsed=GetGameTimer()-a.stepTime
    if a.game.type=='drill' then
        if elapsed<350 then return {error='Mesure trop rapide.'} end
        local oldStep=c.step; local oldChallenge=c.obstacle and c.obstacle.kind
        local ok,err=S.drill(a.game,c,input.pressure,elapsed/1000,input.alignment); a.stepTime=GetGameTimer()
        if not ok then release(src,true); return {error=err} end
        local step=c.step
        local activity=states[a.store].activities['safe:'..a.point]
        if activity then activity.progress=math.floor(c.depth); activity.step=step; activity.challenge=c.obstacle and c.obstacle.kind end
        if step~=oldStep or oldChallenge~=(c.obstacle and c.obstacle.kind) then broadcast(a.store) end
        if c.depth>=100 then a.solved=true; return {solved=true} end
        return {heat=c.heat,depth=c.depth,target=c.target,step=c.step,obstacle=c.obstacle}
    end
    local angle=input.angle
    local valid=type(angle)=='number' and angle==angle and angle>=0 and angle<360 and D.angle(angle,c.target)<=a.game.tolerance
    if a.game.type=='dial' then valid=valid and input.direction==c.direction
    else valid=valid and math.abs(angle-c.target)<=a.game.tolerance and type(input.phase)=='number' and input.phase==input.phase and input.phase>=0 and input.phase<360 and D.angle(input.phase,c.phase)<=a.game.tolerance*3 end
    if not valid or elapsed<math.max(900,a.game.holdMs) then
        release(src,true); return {error='Combinaison incorrecte.'}
    end
    c.step=c.step+1; a.stepTime=GetGameTimer(); c.direction=-c.direction
    if c.step>a.game.steps then a.solved=true; return {solved=true} end
    c.target=math.random(20,339); c.phase=math.random(30,329)
    local activity=states[a.store].activities['safe:'..a.point]; if activity then activity.step=c.step end
    broadcast(a.store)
    return {target=c.target,phase=c.phase,step=c.step,direction=c.direction}
end)
callback('finish',function(src,token,success)
    local a=actions[src]; if not a or a.token~=token or a.stage=='police' then return {error='Action expirée.'} end
    if success~=true then release(src,true); return {ok=true} end
    if not B.canRob(src) then release(src,false);return {error='Votre métier ne permet pas de participer à un braquage.'} end
    local store=storeById(a.store); local state=states[a.store]
    if not near(src,store,a.position,a.stage=='intimidate' and 5 or 2.5) or os.time()>a.expires then release(src,true); return {error='Action interrompue.'} end
    if a.stage=='safe' and not a.solved or a.stage~='safe' and os.time()-a.started<a.duration then return {error='Action trop rapide.'} end
    -- Les objets consommés au départ ne doivent pas être requis une seconde fois.
    local rule=D.copy(a.settings.requirements[a.stage] or {weapons={},items={},equipped=false}); rule.items={}
    for _, i in ipairs(a.items) do if i.consume~='start' and not (a.dropped and i.consume=='success') then rule.items[#rule.items+1]=i end end
    rule.itemMode='all'
    local valid=D.requirements(rule,function(w) return B.weapon(src,w) end,function(w) return GetSelectedPedWeapon(GetPlayerPed(src))==joaat(w) end,function(i) return B.count(src,i) end,function(row)return RequiredInventory.count(src,row)end)
    if not valid then release(src,false); return {error='Conditions de fin non remplies.'} end
    if a.stage=='intimidate' and math.random(100)<=a.settings.refusalChance then
        release(src,true,'clerk_refused'); finishStore(a.store,'clerk_refused')
        for _, pid in ipairs(GetPlayers()) do if B.police(tonumber(pid)) then TriggerClientEvent('cdt_market_light:alert',tonumber(pid),store.label,store.center) end end
        return {error='Le commerçant refuse et déclenche l’alarme. Le magasin passe en recharge.'}
    end
    local rewards={}
    if a.stage=='collect' then
        rewards={a.reward}
        for _, reward in ipairs(rewards) do
            if not B.canReward(src,reward,reward.amount) and a.bestEffort and reward.kind=='item' then
                local low,high=0,reward.amount-1
                while low<high do
                    local amount=math.ceil((low+high)/2)
                    if B.canReward(src,reward,amount) then low=amount else high=amount-1 end
                end
                if low>0 then reward.amount=low end
            end
            if not B.canReward(src,reward,reward.amount) then release(src,false); return {error='Inventaire plein ou récompense indisponible. Libère de la place puis réessaie.',continue=true} end
        end
    end
    if a.stage=='register' then
        if not a.dropped and not dropRegister(a) then release(src,false);return {error='Impossible de préparer le sac.'} end
    elseif not consume(src,a.items,'success') then release(src,false); return {error='Objet requis indisponible.'} end
    if state.activities then state.activities[activityKey(a)]=nil end
    if a.stage=='intimidate' then
        Stats.activate(statistics,a.store)
        state.phase='active'; state.endsAt=os.time()+a.settings.maxDuration; state.lastPresence=os.time()
        globalUntil=os.time()+a.settings.globalCooldown
        actions[src]=nil
        if not persist() then ready=false; return {error='Échec de sauvegarde. Ressource verrouillée.'} end
        broadcast(a.store); audit('started',src,a.store)
        if math.random(100)<=a.settings.alertChance then
            local sessionEnd=state.endsAt
            SetTimeout(a.settings.alertDelay*1000,function()
                if states[a.store]~=state or state.phase~='active' or state.endsAt~=sessionEnd then return end
                for _, pid in ipairs(GetPlayers()) do if B.police(tonumber(pid)) then TriggerClientEvent('cdt_market_light:alert',tonumber(pid),store.label,store.center) end end
                TriggerEvent('cdt_market_light:server:dispatch',a.store,store.label,store.center)
            end)
        end
        return {ok=true,message='Le magasin peut être braqué par tous les joueurs présents.'}
    end
    if a.stage=='safe' then
        local safeState=state.safes[a.point]
        safeState.chunks=Loot.prepare(S.loot(a.safeConfig.loot),Config.lootProps or {})
        safeDebug('stock_prepared',{player=src,store=a.store,point=a.point,chunks=safeState.chunks})
        safeState.openedAt=os.time();safeState.method=a.game.type
        safeState.status=#safeState.chunks>0 and 'open' or 'looted'
        local record=Stats.reserve(statistics,a.store,'safe',a.point,{},GetPlayerName(src),a.token,os.time())
        if record then record.status='opened';record.openedAt=os.time() end
        actions[src]=nil
        if not persist() then return {error='Échec de sauvegarde de l’ouverture. Aucun paiement effectué.'} end
        broadcast(a.store);audit('safe_opened',src,a.store,{point=a.point})
        if D.completed(store,state) then finishStore(a.store,'completed') end
        return {ok=true,message=#safeState.chunks>0 and 'Coffre ouvert. Récupère les objets et les billets à l’intérieur.' or 'Le coffre est vide.'}
    end
    -- Marquer et écrire AVANT paiement : un redémarrage ne doit pas rejouer un gain.
    if a.stage=='register' then
        actions[src]=nil
        if not persist() then return {error='Échec de sauvegarde du sac.'} end
        broadcast(a.store)
        local nextAction
        if a.autoRegisters and state.phase=='active' and not D.allRegisters(state) then nextAction=beginAction(src,a.store,'register',nil,nil,nil,registerChain) end
        if nextAction and nextAction.error then audit('register_chain_stopped',src,a.store,{reason=nextAction.error});nextAction=nil end
        return {ok=true,next=nextAction,message='Sac déposé au sol. Ramasse-le pour récupérer son contenu.'}
    end
    do
        local safeState=state.safes[a.point];local chunk=Loot.find(safeState,a.chunk)
        if not chunk or chunk.status~='reserved' then return {error='Lot expiré.'} end
        if a.reward.amount<chunk.amount then chunk.amount=chunk.amount-a.reward.amount;chunk.status='ready' else chunk.status='taken' end
        if Loot.empty(safeState) then safeState.status='looted' end
    end
    local payment,offset=Stats.reserve(statistics,a.store,a.stage=='collect' and 'safe' or a.stage,a.point,rewards,GetPlayerName(src),a.token,os.time(),a.stage=='collect')
    actions[src]=nil
    if not persist() then ready=false; return {error='Échec de sauvegarde. Aucun paiement effectué.'} end
    broadcast(a.store)
    local paid=true; local summary={}
    for index, reward in ipairs(rewards) do
        local success=B.reward(src,reward,reward.amount); paid=paid and success
        safeDebug('payment',{player=src,store=a.store,point=a.point,chunk=a.chunk,kind=reward.kind,name=reward.name,amount=reward.amount,success=success,inventory=B.inventory})
        Stats.payment(statistics,a.store,payment,index+(offset or 0),success)
        audit(success and 'reward_paid' or 'reward_failed',src,a.store,{kind=reward.kind,name=reward.name,amount=reward.amount,point=a.point,token=a.token})
        if success then summary[#summary+1]=('%d %s'):format(reward.amount,reward.name) end
    end
    if payment then
        payment.status='paid'
        for _,line in ipairs(payment.loot) do if line.status=='failed' then payment.status='payment_failed' elseif line.status=='unknown' and payment.status~='payment_failed' then payment.status='payment_pending' end end
        if a.stage=='collect' and state.safes[a.point].status=='open' and payment.status=='paid' then payment.status='partial' end
    end
    if not persist() then return {error='Paiement traité mais suivi SQL indisponible. Consulter les journaux.'} end
    if D.completed(store,state) then finishStore(a.store,'completed') end
    if not paid then return {error='Attribution impossible. Point verrouillé ; un administrateur peut consulter le journal et régulariser.'} end
    return {ok=true,received=D.copy(rewards),message=#summary>0 and 'Butin récupéré : '..table.concat(summary,', ')..'.' or 'Le coffre est vide.',
        inventory={store=a.store,point=a.point,label=a.safeConfig.label,chunks=D.copy(state.safes[a.point].chunks or {}),canTake=Loot.collectable(state,a.point),revision=revision},
        sync={states=states,revision=revision,globalUntil=globalUntil,serverTime=os.time()}}
end)
callback('pickupBag',function(src,id,point)
    if not B.canRob(src) then return {error='Votre métier ne permet pas de participer à un braquage.'} end
    local store=type(id)=='string' and storeById(id);local state=store and states[id]
    local bag=state and state.bags and state.bags[point]
    if not store or not store.enabled or not bag or bag.status~='ready' or os.time()<(bag.availableAt or 0) or not near(src,store,bag.position,2.5) then return {error='Sac indisponible ou trop éloigné.'} end
    local reward=bag.reward
    if not B.canReward(src,reward,reward.amount) then return {error='Inventaire plein. Libère de la place puis réessaie.'} end
    bag.status='taken'
    local payment=Stats.reserve(statistics,id,'register',point,{reward},GetPlayerName(src),'bag:'..id..':'..point..':'..bag.droppedAt,os.time(),false,bag.session)
    if not persist() then return {error='Échec de sauvegarde. Aucun paiement effectué.'} end
    broadcast(id)
    local paid=B.reward(src,reward,reward.amount)
    Stats.payment(statistics,id,payment,1,paid)
    if payment then payment.status=paid and 'paid' or 'payment_failed' end
    audit(paid and 'bag_paid' or 'bag_payment_failed',src,id,{point=point,reward=reward})
    if not persist() then return {error='Paiement traité mais suivi indisponible. Consulter les journaux.'} end
    if D.completed(store,state) and state.phase=='active' then finishStore(id,'completed') end
    if not paid then return {error='Attribution impossible. Consulter un administrateur.'} end
    return {ok=true,message=('Sac récupéré : %d %s.'):format(reward.amount,reward.name)}
end)
callback('debugMinigame',function(src,kind,difficulty)
    if not B.admin(src) then return {error='Accès refusé.'} end
    if kind~='dial' or type(difficulty)~='string' or not S.presets[difficulty] then
        return {error='Utilisation : /marketlightminigame easy|normal|hard|expert'}
    end
    return {game=S.resolve({type=kind,difficulty=difficulty})}
end)
callback('admin',function(src)
    if not B.admin(src) then return {error='Accès administrateur refusé.'} end
    moduleManager.open(src)
    local custom=require 'server.inventory_custom'
    return {config=config,statistics=statistics,revision=configRevision,states=states,framework=B.framework,inventory=B.inventory,globalUntil=globalUntil,serverTime=os.time(),safePresets=S.presets,administration=Administration.current(Config),administrationRevision=administrationRevision,canAdminister=true,localization=Administration.preferences(Config).localization,customInventory={configured=custom.configured==true,resource=custom.resource}}
end)
callback('saveAdministration',function(src,settings,expectedRevision)
    if not B.admin(src) then return {error='Accès administrateur ou propriétaire requis.'}end
    if type(settings)~='table' or #json.encode(settings)>40000 then return {error='Réglages administratifs trop volumineux ou invalides.'}end
    if expectedRevision~=administrationRevision then return {error='Réglages administratifs modifiés. Recharge avant d’enregistrer.'}end
    settings=Light.administration(settings,Administration.current(Config))
    local valid,why=Administration.validate(settings);if not valid then return {error=why}end
    for _,state in pairs(states)do if state.phase=='active' or state.phase=='intimidating' or state.phase=='investigation' or state.phase=='reopening'then return {error='Termine ou réinitialise les interventions avant de changer les réglages administratifs.'}end end
    if next(actions)then return {error='Une action est encore en cours.'}end
    local previous=Administration.current(Config)
    local changed=settings.framework~=previous.framework or settings.inventory~=previous.inventory or settings.inventory=='custom'
    Administration.apply(Config,settings)
    if changed then
        local ok,err=pcall(B.init)
        if not ok then
            Administration.apply(Config,previous);if not pcall(B.init)then ready=false end
            return {error='Bridge indisponible : '..tostring(err)}
        end
    end
    if not write('administration',{settings=settings,revision=administrationRevision+1})then
        Administration.apply(Config,previous);if changed then pcall(B.init)end;ready=false
        return {error='Échec de sauvegarde des réglages administratifs.'}
    end
    administrationRevision=administrationRevision+1
    broadcast(nil,true);audit('administration_saved',src,nil)
    return {ok=true,administration=Administration.current(Config),revision=administrationRevision,framework=B.framework,inventory=B.inventory}
end)
callback('newStoreId',function(src)
    if not B.admin(src) then return {error='Accès administrateur refusé.'} end
    repeat sequence=sequence+1 until not storeById(('market_%s_%s'):format(os.time(),sequence))
    return {id=('market_%s_%s'):format(os.time(),sequence)}
end)
callback('teleportStore',function(src,id)
    if not B.admin(src)then return {error='Accès administrateur refusé.'}end
    local store=type(id)=='string' and storeById(id)
    if not store then return {error='Supérette inconnue ou non enregistrée.'}end
    if GetPlayerRoutingBucket(src)~=0 then return {error='Reviens dans la dimension principale avant de te téléporter.'}end
    return {ok=true,point=D.copy(store.center),label=store.label}
end)
callback('statistics',function(src)
    if not B.admin(src) then return {error='Accès administrateur refusé.'} end
    return {statistics=statistics,states=states,globalUntil=globalUntil,serverTime=os.time()}
end)
callback('backup',function(src)
    if not B.admin(src) then return {error='Accès refusé.'} end
    local saved=read('config.backup'); if saved then saved.config=Light.config(S.migrate(saved.config)) end
    if not saved or not D.validate(saved.config) then return {error='Aucune sauvegarde valide disponible.'} end
    return {config=saved.config}
end)
local function anyActive() for id, st in pairs(states) do if st.phase=='active' or st.phase=='intimidating' or st.phase=='investigation' or st.phase=='reopening' then return true end end return false end
callback('save',function(src,payload,expectedRevision)
    if not B.admin(src) then return {error='Accès refusé.'} end
    if expectedRevision~=configRevision then return {error='Un administrateur a modifié la configuration. Recharge avant de sauvegarder.'} end
    if anyActive() then return {error='Termine ou réinitialise les braquages et interventions avant de modifier la configuration.'} end
    if type(payload)~='table' or #json.encode(payload)>250000 then return {error='Configuration trop volumineuse.'} end
    payload=Light.config(payload)
    local ok,err=D.validate(payload); if not ok then return {error=err} end
    local nextStates={}
    for _,store in ipairs(payload.stores) do
        local old=states[store.id] or D.state(store);local base=D.state(store)
        base.phase=old.phase;base.cooldownUntil=old.cooldownUntil;base.clerkCalm=old.clerkCalm;base.clerkFrightened=old.clerkFrightened
        if old.phase=='cooldown' then
            base.bags=D.copy(old.bags or {})
            for id in pairs(base.registers) do if old.registers[id]=='looted' then base.registers[id]='looted' end end
            for id in pairs(base.safes) do if old.safes[id] then base.safes[id]=D.copy(old.safes[id]) end end
        end
        nextStates[store.id]=base
    end
    if not Storage.writeMany({['config.backup']={config=config},config={config=payload,revision=configRevision+1},state={states=nextStates,globalUntil=globalUntil}}) then
        ready=false; return {error='Enregistrement SQL impossible. Ressource verrouillée.'}
    end
    config=D.copy(payload); configRevision=configRevision+1; states=nextStates
    broadcast(nil,true); audit('configuration_saved',src,nil,{revision=configRevision})
    return {ok=true,revision=configRevision}
end)
callback('reset',function(src,id)
    if not B.admin(src) then return {error='Permission de réinitialisation refusée.'} end
    local store=storeById(id); if not store then return {error='Magasin inconnu.'} end
    for pid,a in pairs(actions) do if a.store==id then actions[pid]=nil; TriggerClientEvent('cdt_market_light:cancel',pid) end end
    Stats.reset(statistics,id,os.time())
    states[id]=D.state(store)
    if not persist() then ready=false; return {error='Échec de sauvegarde.'} end
    broadcast(id); audit('reset',src,id)
    return {ok=true,message='Supérette réinitialisée. Le délai global reste applicable.'}
end)
callback('deleteStore',function(src,id,expectedRevision)
    if not B.admin(src) then return {error='Accès administrateur refusé.'} end
    if expectedRevision~=configRevision then return {error='Configuration modifiée par un autre administrateur. Recharge avant de supprimer.'} end
    if type(id)~='string' or not storeById(id) then return {error='Supérette inconnue.'} end
    local nextConfig=D.copy(config)
    for index,store in ipairs(nextConfig.stores) do if store.id==id then table.remove(nextConfig.stores,index);break end end
    local nextStates=D.copy(states);nextStates[id]=nil
    local nextSessions=D.copy(robberySessions);nextSessions[id]=nil
    local nextStatistics=D.copy(statistics);Stats.finish(nextStatistics,id,'deleted',os.time())
    local nextRevision=configRevision+1
    if not Storage.writeMany({['config.backup']={config=config},config={config=nextConfig,revision=nextRevision},state={states=nextStates,globalUntil=globalUntil},statistics=nextStatistics}) then
        ready=false;return {error='Suppression non enregistrée : sauvegarde indisponible.'}
    end
    for player,action in pairs(actions) do if action.store==id then actions[player]=nil;TriggerClientEvent('cdt_market_light:cancel',player) end end
    config=nextConfig;configRevision=nextRevision;states=nextStates;statistics=nextStatistics;robberySessions=nextSessions
    broadcast(nil,true);audit('store_deleted',src,id)
    return {ok=true,revision=configRevision,states=states,message='Supérette supprimée et modification appliquée.'}
end)
AddEventHandler('playerDropped',function()
    local src=source
    while operating do Wait(0) end
    operating=true
    local ok,err=xpcall(function() release(src,false) end,debug.traceback)
    busy[src]=nil;operating=false
    if not ok then ready=false;print('[cdt_marketrobbery_light] Déconnexion : ressource verrouillée après erreur : '..tostring(err)) end
    for key in pairs(limits) do if key:match('^'..src..':') then limits[key]=nil end end
    -- L'initiateur ne possède pas la session : son départ ne termine pas le magasin.
end)
CreateThread(function()
    local ok,err=xpcall(function()
        Storage.init()
        statistics=read('statistics') or {}
        for id in pairs(statistics) do Stats.finish(statistics,id,'interrupted',os.time()) end
        local administrative=read('administration')
        if administrative then
            local valid,why=Administration.validate(administrative.settings);assert(valid,why)
            Administration.apply(Config,administrative.settings);administrationRevision=tonumber(administrative.revision)or 0
        end
        -- Le convar explicite fixe la langue au démarrage, même avec une ancienne sauvegarde.
        Config.language=Locale.defaultLanguage(Config.language)
        B.init()
        local saved=read('config'); if saved then config=saved.config; configRevision=tonumber(saved.revision) or 0 end
        config=Light.config(S.migrate(config))
        local valid,why=D.validate(config); assert(valid,why)
        assert(write('config',{config=config,revision=configRevision}),'Impossible de sauvegarder la configuration SQL')
        local savedState=read('state') or {}; globalUntil=tonumber(savedState.globalUntil) or 0
        for _, s in ipairs(config.stores) do
            local old=savedState.states and savedState.states[s.id]; local st=D.state(s)
            if old then
                local preserve=old.phase=='active' or old.phase=='intimidating' or old.phase=='investigation' or old.phase=='reopening' or old.phase=='cooldown' and (tonumber(old.cooldownUntil) or 0)>os.time()
                if preserve then
                    st.bags=D.copy(old.bags or {})
                    st.clerkCalm=old.clerkCalm;st.clerkFrightened=old.clerkFrightened
                    for id in pairs(st.registers) do if old.registers and old.registers[id]=='looted' then st.registers[id]='looted' end end
                    for id in pairs(st.safes) do
                        if old.safes and old.safes[id] then
                            st.safes[id]=D.copy(old.safes[id])
                            st.safes[id].status=st.safes[id].openedAt and (Loot.empty(st.safes[id]) and 'looted' or 'open') or 'ready'
                            for _,chunk in ipairs(st.safes[id].chunks or {}) do if chunk.status=='reserved' then chunk.status='ready' end end
                        end
                    end
                end
                if old.phase=='active' or old.phase=='intimidating' then st.phase='cooldown'; st.cooldownUntil=os.time()+D.settings(config,s).cooldown
                elseif old.phase=='investigation' then st.phase='investigation';st.cooldownUntil=tonumber(old.cooldownUntil) or os.time()+D.settings(config,s).cooldown
                elseif old.phase=='reopening' then st.phase='reopening';st.reopensAt=tonumber(old.reopensAt) or os.time()
                elseif (tonumber(old.cooldownUntil) or 0)>os.time() then st.phase='cooldown'; st.cooldownUntil=old.cooldownUntil end
            end
            states[s.id]=st
        end
        assert(persist(),'Impossible de sauvegarder les états en SQL')
        ready=true; broadcast(nil,true); print(('[cdt_marketrobbery_light] Prêt : %s / %s'):format(B.framework,B.inventory))
    end,debug.traceback)
    if not ok then print('[cdt_marketrobbery_light] ARRÊT : '..err); return end
    while ready do
        Wait(1000)
        if not operating and ready then
        operating=true
        local tickOk,tickError=xpcall(function()
        local now=os.time()
        expireScenes()
        for src,a in pairs(actions) do
            if a.stage~='police' and not B.canRob(src) then
                release(src,false);TriggerClientEvent('cdt_market_light:cancel',src)
            else
            if a.stage=='register' and now<=a.expires and near(src,storeById(a.store),a.position,2.5) then dropRegister(a) end
            if now>a.expires or not near(src,storeById(a.store),a.position,a.stage=='intimidate' and 5 or 2.5) then
                local ped=GetPlayerPed(src)
                safeDebug('action_cancelled',{player=src,stage=a.stage,store=a.store,expired=now>a.expires,bucket=GetPlayerRoutingBucket(src),health=ped and ped~=0 and GetEntityHealth(ped) or nil,position=ped and ped~=0 and GetEntityCoords(ped) or nil,expected=a.position,center=storeById(a.store).center,radius=storeById(a.store).radius})
                release(src,true,'expired_or_invalid_position'); TriggerClientEvent('cdt_market_light:cancel',src)
            end
            end
        end
        for id,st in pairs(states) do
            if st.phase=='active' then
                local present=false
                for _, player in ipairs(GetPlayers()) do
                    local src=tonumber(player)
                    local participant=robberySessions[id] and robberySessions[id].participants and robberySessions[id].participants[tostring(src)]
                    if B.canRob(src) and (not B.police(src) or participant) and near(src,storeById(id)) then present=true;break end
                end
                if present then st.lastPresence=now end
                if now>=st.endsAt or now-(st.lastPresence or now)>=D.settings(config,storeById(id)).abandonDelay then finishStore(id,'expired_or_abandoned') end
            end
        end
        end,debug.traceback)
        operating=false
        if not tickOk then
            ready=false
            print('[cdt_marketrobbery_light] Boucle serveur : ressource verrouillée après erreur : '..tostring(tickError))
        end
        end
    end
end)
-- Aucune écriture différée : les transitions sont déjà validées en SQL.
