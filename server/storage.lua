-- Cache intégral en mémoire ; écritures synchrones avant confirmation/paiement.
local Storage={}
local cache={}
local function decode(raw,name)
    local ok,value=pcall(json.decode,raw)
    assert(ok and type(value)=='table','Stockage illisible : '..name)
    return value
end
local upsert='INSERT INTO `cdt_marketrobbery_light_data` (`name`, `payload`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `payload` = VALUES(`payload`)'

function Storage.init()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `cdt_marketrobbery_light_data` (
        `name` VARCHAR(32) NOT NULL PRIMARY KEY,
        `payload` LONGTEXT NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    cache={}
    for _,row in ipairs(MySQL.query.await('SELECT `name`, `payload` FROM `cdt_marketrobbery_light_data`')) do
        decode(row.payload,row.name)
        cache[row.name]=row.payload
    end
    -- Import atomique, uniquement pour les clés absentes. Les fichiers restent intacts.
    local imported={}
    for _,name in ipairs({'config','config.backup','state'}) do
        if not cache[name] then
            local raw=LoadResourceFile(GetCurrentResourceName(),'data/'..name..'.json')
            if raw then imported[name]=decode(raw,name..'.json') end
        end
    end
    assert(Storage.writeMany(imported),'Import SQL impossible')
end

function Storage.read(name)
    return cache[name] and decode(cache[name],name) or nil
end

function Storage.writeMany(values)
    local queries,pending={},{}
    for name,value in pairs(values) do
        local raw=json.encode(value)
        if cache[name]~=raw then
            queries[#queries+1]={query=upsert,values={name,raw}}
            pending[name]=raw
        end
    end
    if #queries==0 then return true end
    local ok,result=pcall(MySQL.transaction.await,queries)
    if not ok or result~=true then
        print('[cdt_marketrobbery_light] Échec SQL : '..tostring(result))
        return false
    end
    -- Ne jamais faire avancer le cache d'écriture avant le commit SQL.
    for name,raw in pairs(pending) do cache[name]=raw end
    return true
end

function Storage.write(name,value) return Storage.writeMany({[name]=value}) end
return Storage
