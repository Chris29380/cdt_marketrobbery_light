-- Outils locaux de l'éditeur. Aucun gain ou droit n'est décidé ici.
MarketAdmin={}
local M=MarketAdmin
local function position(p) return {x=p.x,y=p.y,z=p.z} end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
function M.context()
    local ped=PlayerPedId(); local p=GetEntityCoords(ped)
    local interior=GetInteriorFromEntity(ped)
    if interior==0 then return nil,'Entre dans un intérieur de supérette avant de lancer la création.' end
    local _,hash=GetInteriorLocationAndNamehash(interior)
    local mapping=(Config.interiorNames or {})[tostring(hash)] or ('Intérieur '..tostring(hash))
    local street,cross=GetStreetNameAtCoord(p.x,p.y,p.z)
    local address=GetStreetNameFromHashKey(street)
    if not address or address=='' then address=GetLabelText(GetNameOfZone(p.x,p.y,p.z)) end
    return {center=position(p),heading=GetEntityHeading(ped),interior=interior,interiorHash=tostring(hash),mapping=mapping,address=address,label=(mapping..' · '..address):sub(1,100)}
end
function M.scan(center,radius,expectedInterior)
    local context,why=M.context(); if not context then return nil,why end
    if expectedInterior and context.interiorHash~=expectedInterior then return nil,'Reviens dans l’intérieur utilisé pour cette création.' end
    if type(center)~='table' or type(center.x)~='number' or type(center.y)~='number' or type(center.z)~='number' or center.x~=center.x or center.y~=center.y or center.z~=center.z or type(radius)~='number' or radius~=radius or radius<3 or radius>80 or distance(center,context.center)>radius then return nil,'Reste dans la zone de la supérette pour lancer la détection.' end
    local registers,safes,seen={},{},{}
    local models={prop_till_01='register',prop_ld_int_safe_01='safe',prop_ld_int_safe_01b='safe',prop_ld_int_safe_01c='safe',prop_ld_int_safe_01d='safe',prop_safe_01='safe',v_ilev_gangsafe='safe'}
    for name,enabled in pairs(Config.detectSafeModels or {}) do if enabled then models[name]='safe' end end
    local hashes={}; for name,kind in pairs(models) do hashes[joaat(name)]={name=name,kind=kind} end
    local function add(entity,info)
        if entity==0 or seen[entity] or not DoesEntityExist(entity) then return end
        seen[entity]=true
        local p=GetEntityCoords(entity)
        local interior=GetInteriorFromEntity(entity)
        if interior==0 then interior=GetInteriorAtCoords(p.x,p.y,p.z) end
        if distance(p,center)>radius or interior~=context.interior then return end
        local entry={x=p.x,y=p.y,z=p.z,heading=GetEntityHeading(entity),model=info.name,modelHash=GetEntityModel(entity)}
        local list=info.kind=='register' and registers or safes
        for _,v in ipairs(list) do if distance(v,entry)<0.15 then return end end
        entry.id=(info.kind=='register' and 'caisse_' or 'coffre_')..(#list+1)
        if info.kind=='register' then entry.replacementModel='p_till_01_s';entry.original={x=p.x,y=p.y,z=p.z,heading=entry.heading,model=info.name} end
        list[#list+1]=entry
    end
    for _,entity in ipairs(GetGamePool('CObject')) do local info=hashes[GetEntityModel(entity)]; if info then add(entity,info) end end
    -- Les objets intégrés au mapping ne sont pas tous présents dans le pool.
    local calls=0
    for hash,info in pairs(hashes) do
        for x=-radius,radius,3 do for y=-radius,radius,3 do
            if x*x+y*y<=radius*radius then
                add(GetClosestObjectOfType(center.x+x,center.y+y,center.z,3.5,hash,false,false,false),info)
                calls=calls+1; if calls%100==0 then Wait(0) end
            end
        end end
    end
    return {registers=registers,safes=safes,interior=context.interiorHash}
end
function M.preview(payload)
    if not payload.preview then return nil end
    local model=payload.preview.model
    if type(model)~='string' then return nil end
    local hash=joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    local ok=pcall(lib.requestModel,hash,5000); if not ok then return nil end
    local p=GetEntityCoords(PlayerPedId())
    local entity
    if payload.preview.kind=='ped' and IsModelAPed(hash) then entity=CreatePed(4,hash,p.x,p.y,p.z,0,false,false)
    elseif not IsModelAPed(hash) and not IsModelAVehicle(hash) then entity=CreateObjectNoOffset(hash,p.x,p.y,p.z,false,false,false) end
    SetModelAsNoLongerNeeded(hash)
    if not entity or entity==0 then return nil end
    if entity then SetEntityAlpha(entity,150,false); SetEntityCollision(entity,false,false); FreezeEntityPosition(entity,false); SetEntityHasGravity(entity,false); SetEntityInvincible(entity,true); if payload.preview.kind=='ped' then SetBlockingOfNonTemporaryEvents(entity,true) end end
    return entity
end
