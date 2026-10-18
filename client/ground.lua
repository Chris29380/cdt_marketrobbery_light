-- Convention : placement = point d'appui ; x/y/z = origine réelle du modèle.
MarketGround={}
local M=MarketGround
local bounds={}
local retired={}
local function reap()
    for i=#retired,1,-1 do
        local status=GetShapeTestResult(retired[i]);if status~=1 then table.remove(retired,i) end
    end
end
function M.release(check)
    if check then for _,handle in pairs(check.handles) do retired[#retired+1]=handle end;check.handles={} end
    reap()
end
local function dimensions(hash)
    if not bounds[hash] then local a,b=GetModelDimensions(hash); bounds[hash]={min=a,max=b} end
    return bounds[hash]
end
local function rotated(x,y,heading)
    local r=math.rad(heading or 0); return x*math.cos(r)-y*math.sin(r),x*math.sin(r)+y*math.cos(r)
end
function M.origin(hash,p,heading)
    local d=dimensions(hash);local x,y=rotated((d.min.x+d.max.x)/2,(d.min.y+d.max.y)/2,heading)
    return {x=p.x-x,y=p.y-y,z=p.z-d.min.z,placement={x=p.x,y=p.y,z=p.z}}
end
function M.contact(hash,p,heading)
    local d=dimensions(hash);local x,y=rotated((d.min.x+d.max.x)/2,(d.min.y+d.max.y)/2,heading)
    return {x=p.x+x,y=p.y+y,z=p.z+d.min.z}
end
local function ray(x,y,top,bottom,ignore)
    RequestCollisionAtCoord(x,y,top)
    return StartShapeTestLosProbe(x,y,top,x,y,bottom,17,ignore,7)
end
function M.support(entity,p,heading)
    reap()
    local d=dimensions(GetEntityModel(entity));local handles={}
    local cx,cy=(d.min.x+d.max.x)/2,(d.min.y+d.max.y)/2
    local hx,hy=(d.max.x-d.min.x)*0.35,(d.max.y-d.min.y)*0.35
    for _,offset in ipairs({{0,0},{-hx,-hy},{hx,-hy},{hx,hy},{-hx,hy}}) do
        local x,y=rotated(offset[1],offset[2],heading)
        handles[#handles+1]=ray(p.x+x,p.y+y,p.z+0.18,p.z-0.18,entity)
    end
    return {handles=handles,point={x=p.x,y=p.y,z=p.z},heading=heading,started=GetGameTimer()}
end
function M.poll(check)
    if check.result~=nil then return check.result end
    local pending=false
    for i,handle in pairs(check.handles) do
        local status,hit,p,normal=GetShapeTestResult(handle)
        if status==1 then pending=true
        else
            check.handles[i]=nil
            if status~=2 or not (hit==true or hit==1) or not normal or normal.z<0.96 or math.abs(p.z-check.point.z)>0.08 then check.invalid=true end
        end
    end
    if not pending then check.result=not check.invalid;return check.result end
    if GetGameTimer()-check.started>1000 then M.release(check);check.result=false;return false end
end
function M.preview(entity,p,heading,normal,check)
    local origin=M.origin(GetEntityModel(entity),p,heading)
    FreezeEntityPosition(entity,false)
    SetEntityCoordsNoOffset(entity,origin.x,origin.y,origin.z,false,false,false);SetEntityHeading(entity,heading)
    if not normal or normal.z<0.96 then M.release(check);return false,nil,origin end
    if check and check.result==nil then
        M.poll(check)
        if check.result==nil then return nil,check,origin end
    end
    if not check or math.abs(check.point.x-p.x)>0.01 or math.abs(check.point.y-p.y)>0.01 or math.abs(check.point.z-p.z)>0.01 or math.abs(check.heading-heading)>0.5 or check.result==false and GetGameTimer()-check.started>250 then check=M.support(entity,p,heading) end
    local valid=M.poll(check)
    if valid then FreezeEntityPosition(entity,true) end
    return valid,check,origin
end
local function findSurface(entity,p,drop)
    local handle=ray(p.x,p.y,p.z+0.18,p.z-drop,entity)
    local started=GetGameTimer()
    repeat
        local status,hit,point,normal=GetShapeTestResult(handle)
        if status==2 then if (hit==1 or hit==true) and normal and normal.z>=0.96 then return point end;return nil end
        if status==0 then return nil end
        Wait(0)
    until GetGameTimer()-started>1000
end
function M.settle(entity,data,isPed)
    if not entity or entity==0 or not DoesEntityExist(entity) then return false end
    FreezeEntityPosition(entity,false);SetEntityHasGravity(entity,false);SetEntityCollision(entity,false,false)
    local hash=GetEntityModel(entity)
    local contact=data.placement or (isPed and {x=data.x,y=data.y,z=data.z-1.0} or M.contact(hash,data,data.heading))
    local surface
    local deadline=GetGameTimer()+1000
    repeat
        surface=findSurface(entity,contact,data.placement and 0.18 or 2.0)
        if not surface then Wait(0) end
    until surface or GetGameTimer()>=deadline
    if not surface then return false end
    if data.placement and math.abs(surface.z-contact.z)>0.08 then return false end
    local origin=M.origin(hash,surface,data.heading)
    SetEntityCoordsNoOffset(entity,origin.x,origin.y,origin.z,false,false,false);SetEntityHeading(entity,data.heading or 0)
    SetEntityCollision(entity,true,true);SetEntityHasGravity(entity,true)
    if isPed then
        -- La boîte du modèle ne représente pas exactement les semelles du ped.
        -- Évaluer ses os après le placement avant de corriger la hauteur réelle.
        Wait(0);if not DoesEntityExist(entity) then return false end
        ForceEntityAiAndAnimationUpdate(entity)
        local left=GetPedBoneCoords(entity,14201,0.0,0.0,0.0)
        local right=GetPedBoneCoords(entity,52301,0.0,0.0,0.0)
        local feet=math.min(left.z,right.z)-0.04
        local delta=surface.z-feet
        if math.abs(delta)>0.6 then return false end
        local at=GetEntityCoords(entity)
        SetEntityCoordsNoOffset(entity,at.x,at.y,at.z+delta,false,false,false)
    else
        -- Cette native est réservée aux objets, pas aux peds.
        PlaceObjectOnGroundProperly(entity)
        local actual=M.contact(hash,GetEntityCoords(entity),data.heading)
        if math.abs(actual.z-surface.z)>0.08 then return false end
    end
    local check=M.support(entity,surface,data.heading or 0)
    repeat
        if not DoesEntityExist(entity) then return false end
        local result=M.poll(check)
        if result~=nil then
            if result then SetEntityCollision(entity,true,true);SetEntityHasGravity(entity,true);FreezeEntityPosition(entity,true) end
            return result
        end
        Wait(0)
    until GetGameTimer()-check.started>1000
    return false
end
function M.capture(model)
    local hash=joaat(model);if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil,'Modèle invalide.' end
    local loaded=pcall(lib.requestModel,hash,5000);if not loaded then return nil,'Chargement du modèle impossible.' end
    local ped=PlayerPedId();local p=GetEntityCoords(ped)
    local surface=findSurface(ped,p,3.0)
    if not surface then SetModelAsNoLongerNeeded(hash);return nil,'Aucun sol stable détecté sous le joueur.' end
    local heading=GetEntityHeading(ped)
    local origin=M.origin(hash,surface,heading);origin.heading=heading;SetModelAsNoLongerNeeded(hash)
    return origin
end
