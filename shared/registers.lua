local R={originalModel='prop_till_01',replacementModel='p_till_01_s'}
-- Phase du geste de lancer du clip holdup_victim_20s.
R.dropPhase=0.82
function R.bagModel(register)return register.bag and register.bag.model or 'prop_poly_bag_01' end
function R.dropPosition(register)
    if register.bag and register.bag.drop then
        local p=register.bag.drop
        return {x=p.x,y=p.y,z=p.z,heading=p.heading or 0,placement=p.placement}
    end
    local v=R.visual(register);local h=math.rad(v.heading)
    return {x=v.x+0.85*math.sin(h),y=v.y-0.85*math.cos(h),z=v.z}
end
function R.original(register)
    local p=register.original or register
    return {x=p.x,y=p.y,z=p.z,heading=p.heading or register.heading or 0,model=p.model or register.model or R.originalModel}
end
function R.visual(register)
    local v={autoLocate=true,x=register.x,y=register.y,z=register.z,heading=register.heading or 0,hideRadius=0.35,openPhase=0.65,offsetX=0,offsetY=0,offsetZ=0}
    for k,value in pairs(register.visual or {}) do v[k]=value end
    -- Ancienne valeur livrée par l'éditeur, située avant l'ouverture du tiroir.
    if v.openPhase==0.32 then v.openPhase=0.65 end
    return v
end
function R.validate(register)
    local function n(v,a,b) return type(v)=='number' and v==v and v>=a and v<=b end
    if register.original~=nil and type(register.original)~='table' then return false,'Caisse originale invalide.' end
    local original=R.original(register)
    if register.bag~=nil then
        local bag=register.bag
        if type(bag)~='table' or type(bag.model)~='string' or #bag.model<1 or #bag.model>80 or not bag.model:match('^[%w_%-]+$') then return false,'Prop du sac de caisse invalide.' end
        local p=bag.drop
        if type(p)~='table' or not n(p.x,-16000,16000) or not n(p.y,-16000,16000) or not n(p.z,-1000,3000) or p.heading~=nil and not n(p.heading,0,360) then return false,'Point de dépôt du sac invalide.' end
        if p.placement~=nil then local v=p.placement;if type(v)~='table' or not n(v.x,-16000,16000) or not n(v.y,-16000,16000) or not n(v.z,-1000,3000) then return false,'Appui du sac invalide.' end end
    end
    if register.model~=nil and register.model~=R.originalModel or original.model~=R.originalModel or register.replacementModel~=nil and register.replacementModel~=R.replacementModel then return false,'Modèle de caisse incompatible avec l’animation : prop_till_01 requis, remplacé par p_till_01_s.' end
    if not n(original.x,-16000,16000) or not n(original.y,-16000,16000) or not n(original.z,-1000,3000) or not n(original.heading,0,360) then return false,'Position de la caisse originale invalide.' end
    if register.duration~=nil and (not n(register.duration,2,300) or register.duration%1~=0) then return false,'Durée de caisse invalide.' end
    if register.reward~=nil then
        local r=register.reward
        if type(r)~='table' or (r.kind~='money' and r.kind~='item') or type(r.name)~='string' or not r.name:match('^[%w_%-]+$') or #r.name>80 or not n(r.min,1,100000) or not n(r.max,r.min,100000) or r.min%1~=0 or r.max%1~=0 then return false,'Gain de caisse invalide.' end
    end
    if register.visual~=nil and type(register.visual)~='table' then return false,'Scène de caisse invalide.' end
    local v=R.visual(register)
    if type(v.autoLocate)~='boolean' or not n(v.x,-16000,16000) or not n(v.y,-16000,16000) or not n(v.z,-1000,3000) or not n(v.heading,0,360) or not n(v.hideRadius,0.1,0.8) or not n(v.openPhase,0.05,0.95) or not n(v.offsetX,-2,2) or not n(v.offsetY,-2,2) or not n(v.offsetZ,-2,2) then return false,'Position ou paramètres de scène invalides.' end
    local distance=math.sqrt((v.x-register.x)^2+(v.y-register.y)^2+(v.z-register.z)^2)
    if distance>3 then return false,'La caisse animée doit rester à moins de 3 m du point.' end
    return true
end
return R
