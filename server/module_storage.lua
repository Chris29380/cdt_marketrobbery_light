-- Conserver les options Premium lors d'un passage temporaire en version gratuite.
local M={}
local function copy(v)
    if type(v)~='table' then return v end
    local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
local function identified(v)
    if type(v)~='table' or #v==0 then return false end
    local seen={}
    for _,item in ipairs(v)do
        if type(item)~='table' or type(item.id)~='string' or seen[item.id]then return false end
        seen[item.id]=true
    end
    return true
end
function M.merge(original,projected,edited)
    if equal(projected,edited)then return copy(original)end
    if type(edited)~='table' or type(original)~='table' or type(projected)~='table'then return copy(edited)end
    if identified(original) or identified(projected) or identified(edited) then
        local old,view,out={},{},{}
        for _,item in ipairs(original)do old[item.id]=item end
        for _,item in ipairs(projected)do view[item.id]=item end
        -- La liste éditée décide de l'ordre, des ajouts et des suppressions.
        for _,item in ipairs(edited)do out[#out+1]=M.merge(old[item.id],view[item.id],item)end
        return out
    end
    if #original>0 or #projected>0 or #edited>0 then return copy(edited)end
    local out,keys={},{}
    for k in pairs(original)do keys[k]=true end
    for k in pairs(projected)do keys[k]=true end
    for k in pairs(edited)do keys[k]=true end
    for k in pairs(keys)do out[k]=M.merge(original[k],projected[k],edited[k])end
    return out
end
function M.reset(Storage)
    if Storage._moduleRaw then
        Storage.read=Storage._moduleRaw.read;Storage.writeMany=Storage._moduleRaw.writeMany
        Storage._moduleRaw=nil
    end
end
function M.install(Storage,Light,Administration,config)
    M.reset(Storage)
    local read,writeMany=Storage.read,Storage.writeMany
    Storage._moduleRaw={read=read,writeMany=writeMany}
    local function projectAdmin(value)return Light.administration(value,Administration.current(config))end
    Storage.read=function(name)
        local value=read(name)
        if name=='administration' and value then value.settings=projectAdmin(value.settings)end
        if name=='state' and value then
            for _,state in pairs(value.states or {})do
                if state.phase=='investigation' or state.phase=='reopening'then
                    state.phase='cooldown';state.cooldownUntil=tonumber(state.cooldownUntil)or os.time()+config.defaults.cooldown
                    state.reopensAt=nil
                end
            end
        end
        return value
    end
    Storage.writeMany=function(values)
        values=copy(values)
        -- Une scène gratuite ne doit pas réutiliser les preuves d'un ancien braquage Premium.
        if values.state then values.police_reports={} end
        for _,key in ipairs({'config','config.backup'})do
            if values[key] and values[key].config then
                local old=read(key=='config.backup' and 'config' or key)
                if old and old.config then values[key].config=M.merge(old.config,Light.config(old.config),values[key].config)end
            end
        end
        if values.administration then
            local old=read('administration')
            if old and old.settings then
                values.administration.settings=M.merge(old.settings,projectAdmin(old.settings),values.administration.settings)
            end
        end
        return writeMany(values)
    end
end
return M
