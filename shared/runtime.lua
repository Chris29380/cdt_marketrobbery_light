-- Contrat du module : seul le noyau Light exécute les scènes et possède les données.
local R={apiVersion=1,module='cdt_marketrobbery_premium'}
local premiumFiles={
    ['server.main']=true,['server.hostages']=true,['server.police']=true,
    ['server.administration']=true,['shared.domain']=true,
    ['shared.hostages']=true,['shared.keybinds']=true,
    ['client.main']=true,['client.hostages']=true,['client.police']=true
}
function R.available()
    if GetResourceState(R.module)~='started' then return false end
    local raw=LoadResourceFile(R.module,'module.json')
    local ok,descriptor=pcall(json.decode,raw or '')
    assert(ok and type(descriptor)=='table' and descriptor.apiVersion==R.apiVersion,
        'cdt_marketrobbery_premium : version du module incompatible avec la Light.')
    return true
end
function R.loader(premium)
    local cache,loading={},{}
    local originalRequire=require
    local env=setmetatable({}, {__index=_G,__newindex=_G})
    local function moduleRequire(name)
        if not premium or not premiumFiles[name] then
            -- Conserver cette frame : ox_lib déduit la ressource depuis la pile.
            -- Un appel terminal peut lui faire chercher dans ox_lib lors d'un callback.
            local result=originalRequire(name)
            return result
        end
        if cache[name]~=nil then return cache[name] end
        assert(not loading[name],'Dépendance circulaire : '..name)
        local filename=name:gsub('%.','/')..'.lua'
        local source=assert(LoadResourceFile(R.module,filename),'Fichier Premium absent : '..filename)
        local chunk=assert(load(source,'@'..R.module..'/'..filename,'t',env))
        loading[name]=true
        local result=chunk()
        loading[name]=nil;cache[name]=result==nil and true or result
        return cache[name]
    end
    rawset(env,'require',moduleRequire)
    return function(name)
        if premium then
            if name=='server.main' or name=='client.main'then cache[name]=nil end
            return moduleRequire(name)
        end
        local filename=name:gsub('%.','/')..'.lua'
        local source=assert(LoadResourceFile(GetCurrentResourceName(),filename),'Fichier Light absent : '..filename)
        return assert(load(source,'@'..GetCurrentResourceName()..'/'..filename,'t',env))()
    end
end
return R
