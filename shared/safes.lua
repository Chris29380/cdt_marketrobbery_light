-- Modèle des coffres et mini-jeux fictifs. Aucune méthode réelle d'effraction.
local S = {}
S.presets = {
    easy={steps=2,tolerance=12,duration=150,attempts=5,penalty=5,speed=50,holdMs=500},
    normal={steps=3,tolerance=7,duration=100,attempts=3,penalty=20,speed=65,holdMs=650},
    hard={steps=4,tolerance=4,duration=80,attempts=2,penalty=40,speed=80,holdMs=1000},
    expert={steps=6,tolerance=2,duration=65,attempts=1,penalty=60,speed=95,holdMs=1300}
}
local function copy(v) if type(v)~='table' then return v end; local r={}; for k,x in pairs(v) do r[k]=copy(x) end; return r end
function S.resolve(game)
    local preset=S.presets[game.difficulty=='custom' and 'normal' or game.difficulty]
    local out=copy(preset or S.presets.normal)
    if game.difficulty=='custom' then for k,v in pairs(game.custom or {}) do out[k]=v end end
    out.type='dial'; return out
end
function S.effective(safe,settings)
    local out=copy(safe); local inherit=type(safe.inherit)=='table' and safe.inherit or {}
    if inherit.minigame then out.minigame=copy(settings.safeMinigame or {type='dial',difficulty='normal'}) end
    if inherit.loot then out.loot=copy(settings.safeLoot or {{kind=settings.safeReward.kind,name=settings.safeReward.name,min=settings.safeReward.min,max=settings.safeReward.max,chance=100}}) end
    if inherit.requiresRegisters then out.requiresRegisters=settings.safeRequiresRegisters end
    out.minigame.type='dial'
    return out
end
function S.migrate(config)
    local out=copy(config)
    out.defaults.safeMinigame=out.defaults.safeMinigame or {type='dial',difficulty='normal'}
    local function dial(game)
        if type(game)=='table' and (game.type=='drill' or game.type=='electronic') then game.type='dial' end
    end
    dial(out.defaults.safeMinigame)
    out.defaults.safeLoot=out.defaults.safeLoot or {{kind=out.defaults.safeReward.kind,name=out.defaults.safeReward.name,min=out.defaults.safeReward.min,max=out.defaults.safeReward.max,chance=100}}
    for _, store in ipairs(out.stores or {}) do
        if store.safes==nil then
            store.safes={}
            if store.safe then
                local old=store.safe; local effective=copy(out.defaults)
                for k,v in pairs(store.settings or {}) do effective[k]=copy(v) end
                store.safes[1]={id=old.id or 'coffre',label='Coffre',x=old.x,y=old.y,z=old.z,heading=0,model='prop_ld_int_safe_01',spawnProp=false,
                    interaction={x=old.x,y=old.y,z=old.z},requiresRegisters=effective.safeRequiresRegisters,
                    loot={{kind=effective.safeReward.kind,name=effective.safeReward.name,min=effective.safeReward.min,max=effective.safeReward.max,chance=100}},
                    minigame={type='dial',difficulty='custom',custom={steps=effective.safeSteps,tolerance=effective.safeTolerance,duration=effective.safeDuration,attempts=effective.safeAttempts,penalty=effective.safePenalty,speed=65,holdMs=650}}}
            end
        end
        dial(store.settings and store.settings.safeMinigame)
        for _,safe in ipairs(store.safes) do dial(safe.minigame) end
        store.safe=nil
    end
    out.schemaVersion=2; return out
end
local function number(v,a,b) return type(v)=='number' and v==v and v>=a and v<=b end
local function integer(v,a,b) return number(v,a,b) and v%1==0 end
local function name(v) return type(v)=='string' and #v>0 and #v<=80 and v:match('^[%w_%-]+$') end
    local function point(p)
        if not (type(p)=='table' and number(p.x,-16000,16000) and number(p.y,-16000,16000) and number(p.z,-1000,3000)) then return false end
        local v=p.placement
        return v==nil or type(v)=='table' and number(v.x,-16000,16000) and number(v.y,-16000,16000) and number(v.z,-1000,3000)
    end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
function S.validate(s,center,radius)
    if type(s)~='table' or not name(s.id) or type(s.label)~='string' or #s.label<1 or #s.label>80 then return false,'Identité du coffre invalide.' end
    if s.inherit~=nil then
        if type(s.inherit)~='table' then return false,'Héritage du coffre invalide.' end
        for key,value in pairs(s.inherit) do if not ({minigame=true,loot=true,requiresRegisters=true})[key] or type(value)~='boolean' then return false,'Héritage du coffre invalide.' end end
    end
    if not point(s) then return false,'Coordonnées du coffre invalides.' end
    if not point(s.interaction) then return false,'Coordonnées du point d’interaction invalides.' end
    local safeDistance=distance(s,center)
    if safeDistance>radius then return false,('Coffre hors zone : %.2f m du centre, rayon autorisé %.2f m. Corrigez sa position ou la zone du magasin.'):format(safeDistance,radius) end
    local interactionDistance=distance(s.interaction,center)
    if interactionDistance>radius then return false,('Point d’interaction hors zone : %.2f m du centre, rayon autorisé %.2f m. Corrigez le point ou la zone du magasin.'):format(interactionDistance,radius) end
    local gap=distance(s,s.interaction)
    if gap>4 then return false,('Point d’interaction trop éloigné du coffre : %.2f m (maximum 4 m). Replacez le point près du coffre dans l’onglet Coffres.'):format(gap) end
    if not name(s.model) or not number(s.heading,0,360) or type(s.spawnProp)~='boolean' or type(s.requiresRegisters)~='boolean' then return false,'Prop ou condition du coffre invalide.' end
    if s.itemRequirements~=nil then
        local rule=s.itemRequirements
        if type(rule)~='table' or not ({none=true,all=true,any=true})[rule.mode] or type(rule.items)~='table' or #rule.items>20 or (rule.mode=='none' and #rule.items>0) then return false,'Objets requis du coffre invalides.' end
        local seen={}
        for _, i in ipairs(rule.items) do
            if type(i)~='table' or not name(i.name) or i.kind~=nil and i.kind~='item' and i.kind~='weapon' or not integer(i.count,1,100) or not ({never=true,start=true,success=true,failure=true})[i.consume] then return false,'Objet requis du coffre invalide ou répété.' end
            local key=(i.kind=='weapon' or i.name:sub(1,7):lower()=='weapon_') and i.name:lower() or i.name
            if seen[key] then return false,'Objet requis du coffre invalide ou répété.' end
            seen[key]=true
        end
    end
    if type(s.loot)~='table' or #s.loot>12 then return false,'Maximum 12 lignes de butin par coffre.' end
    for _, r in ipairs(s.loot) do
        if type(r)~='table' or (r.kind~='money' and r.kind~='item') or not name(r.name) or not integer(r.min,1,100000) or not integer(r.max,r.min,100000) or not integer(r.chance,0,100) then return false,'Butin du coffre invalide.' end
    end
    if s.visual~=nil then
        if type(s.visual)~='table' then return false,'Affichage du coffre invalide.' end
        for _,key in ipairs({'bodyModel','doorModel'}) do if s.visual[key]~=nil and not name(s.visual[key]) then return false,'Modèle du coffre ouvrant invalide.' end end
        for _,key in ipairs({'doorOffsetX','doorOffsetY','doorOffsetZ','lootOffsetX','lootOffsetY','lootOffsetZ'}) do if s.visual[key]~=nil and not number(s.visual[key],-3,3) then return false,'Décalage du coffre ouvrant invalide.' end end
        if s.visual.openAngle~=nil and not number(s.visual.openAngle,-160,160) then return false,'Angle de porte invalide.' end
    end
    for _,r in ipairs(s.loot) do
        if r.model~=nil and not name(r.model) then return false,'Prop de butin invalide.' end
        if r.label~=nil and (type(r.label)~='string' or #r.label>80) then return false,'Nom de butin invalide.' end
    end
    local g=s.minigame
    if type(g)~='table' or g.type~='dial' or (not S.presets[g.difficulty] and g.difficulty~='custom') then return false,'Mini-jeu ou difficulté invalide.' end
    if g.difficulty=='custom' then
        if type(g.custom)~='table' then return false,'Paramètres personnalisés manquants.' end
        local ranges={steps={1,8},tolerance={2,25},duration={15,600},attempts={1,20},penalty={0,600},speed={20,140},holdMs={400,3000}}
        for k in pairs(g.custom) do if not ranges[k] then return false,'Paramètre de mini-jeu inconnu.' end end
        for k,r in pairs(ranges) do if not integer(g.custom[k],r[1],r[2]) then return false,'Paramètre de mini-jeu invalide : '..k end end
    end
    return true
end
function S.loot(entries,random)
    random=random or math.random
    local out,index={},{}
    for _, r in ipairs(entries) do
        if random(1,100)<=r.chance then
            local key=r.kind..':'..r.name; local amount=random(r.min,r.max)
            if index[key] then index[key].amount=index[key].amount+amount
            else local line={kind=r.kind,name=r.name,amount=amount,model=r.model,label=r.label}; out[#out+1]=line; index[key]=line end
        end
    end
    return out
end
function S.challenge(game)
    return {target=math.random(game.type=='drill' and 35 or 20,game.type=='drill' and 75 or 339),phase=math.random(30,329),direction=1,step=1,heat=0,depth=0}
end
function S.drill(game,state,pressure,elapsed,alignment)
    if not number(pressure,0,100) then return false,'Pression invalide.' end
    local dt=math.max(0,math.min(elapsed,1.2)); local band=math.max(4,game.tolerance*1.5)
    state.step=state.step or 1
    if state.obstacle then
        local obstacle=state.obstacle
        obstacle.elapsed=obstacle.elapsed+math.max(0,elapsed)
        if obstacle.elapsed>obstacle.limit then return false,'Défi de couche expiré.' end
        local valid
        if obstacle.kind=='release' then valid=pressure<5
        elseif obstacle.kind=='align' then
            alignment=alignment or 0
            if not number(alignment,-100,100) then return false,'Alignement invalide.' end
            valid=pressure<5 and math.abs(alignment-obstacle.target)<=game.tolerance
        else valid=math.abs(pressure-state.target)<=math.max(3,game.tolerance*0.7) end
        obstacle.progress=valid and math.min(obstacle.required,obstacle.progress+dt) or 0
        state.heat=math.max(0,state.heat+dt*(pressure<5 and -22 or valid and 2 or 18))
        if state.heat>=100 then return false,'Surchauffe : tentative échouée.' end
        if obstacle.progress>=obstacle.required then
            state.obstacle=nil;state.step=state.step+1;state.target=math.random(35,75)
        end
        return true
    end
    local error=math.abs(pressure-state.target)
    if pressure<1 then state.heat=math.max(0,state.heat-dt*22)
    else
        state.heat=math.max(0,state.heat+dt*(pressure/100*12+(error>band and 25 or -7)))
        if error<=band and state.heat<95 then
            local boundary=state.step/game.steps*100
            state.depth=math.min(boundary,state.depth+dt*100/(game.steps*3))
            if state.depth>=boundary and state.step<game.steps then
                local kind=({'release','align','steady'})[(state.step-1)%3+1]
                state.obstacle={kind=kind,target=math.random(-70,70),elapsed=0,limit=math.max(5,12-game.steps),required=game.holdMs/1000+0.4,progress=0}
            end
        end
    end
    if state.heat>=100 then return false,'Surchauffe : tentative échouée.' end
    return true
end
return S
