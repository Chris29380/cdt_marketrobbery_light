local Runtime=require 'shared.runtime'
local premium=Runtime.available()
require('server.module_storage').reset(require 'server.storage')
if not premium then
    require('server.module_storage').install(require 'server.storage',require 'server.light',require 'server.administration',Config)
end
-- Valeur unique, décidée par le serveur ; les clients attendent sa réplication.
GlobalState.cdtMarketRobberyRuntime=premium and 'premium' or 'free'
lib.callback.register('cdt_market_light:runtimeMode',function()
    return {apiVersion=Runtime.apiVersion,premium=premium}
end)
Runtime.loader(premium)('server.main')
print('[cdt_marketrobbery_light] Mode '..(premium and 'Premium' or 'gratuit')..' ; API module '..Runtime.apiVersion)
for _,event in ipairs({'onResourceStart','onResourceStop'})do
    AddEventHandler(event,function(name)
        if name==Runtime.module then print('[cdt_marketrobbery_light] Module modifié : utilisez Détecter les modules dans la configuration, ou redémarrez cdt_marketrobbery_light.')end
    end)
end
