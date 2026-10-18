-- Point d'entrée unique pour les messages, le butin et les alertes police.
local Locale=require 'shared.locale'
local Providers=require 'shared.notifications'
local Custom=require 'client.notifications_custom'
local N={}
local function info(kind)return kind=='inform' and 'info' or kind end
local adapters={
    ox={resource='ox_lib',send=function(d)return lib.notify({title=d.title,description=d.message,type=d.type,duration=d.duration})end},
    okok={resource='okokNotify',send=function(d)return exports.okokNotify:Alert(d.title,d.message,d.duration,info(d.type),true)end},
    wasabi={resource='wasabi_notify',send=function(d)return exports.wasabi_notify:notify(d.title,d.message,d.duration,info(d.type))end},
    brutal={resource='brutal_notify',send=function(d)return exports.brutal_notify:SendAlert(d.title,d.message,d.duration,info(d.type),true)end},
    mythic={resource='mythic_notify',send=function(d)return exports.mythic_notify:DoCustomHudText(d.type=='warning' and 'inform' or d.type,d.message,d.duration)end},
    quasar={resource='qs-interface',send=function(d)
        local icons={success='fas fa-check',error='fas fa-exclamation-circle',warning='fas fa-exclamation-triangle',inform='fas fa-info-circle'}
        return exports['qs-interface']:AddNotify(d.message,d.title,d.duration,icons[d.type])
    end},
    qb={resource='qb-core',send=function(d)return exports['qb-core']:GetCoreObject().Functions.Notify(d.message,(d.type=='inform' or d.type=='warning') and 'primary' or d.type,d.duration)end},
    esx={resource='es_extended',send=function(d)return exports.es_extended:getSharedObject().ShowNotification(d.message,info(d.type),d.duration)end},
    custom={send=function(d)
        if Custom.configured~=true or type(Custom.notify)~='function' then return false end
        if Custom.resource and GetResourceState(Custom.resource)~='started' then return false end
        return Custom.notify(d)
    end}
}
local function internal(d)
    if d.category=='loot' then SendNUIMessage({type='lootToast',items=d.items,duration=d.duration})
    elseif d.category=='police' then SendNUIMessage({type='dispatch',location=d.location,duration=d.duration})
    else SendNUIMessage({type='toast',message=d.message,kind=d.type,duration=d.duration})end
end
function N.send(data)
    local provider=Config.notifications
    if provider==false and not data.administrative then return false end
    if provider==nil or provider==false then provider='cdt' end
    local kind=data.type or 'inform'
    if not ({inform=true,success=true,error=true,warning=true})[kind] then kind='inform' end
    local d={title=Locale.text(data.title or 'Braquage de supérette',Config.language),message=Locale.text(tostring(data.message or ''),Config.language),type=kind,
        duration=data.duration or Config.notificationDuration or 5000,category=data.category or 'message',items=data.items,location=data.location}
    local adapter=adapters[provider]
    if Providers[provider] and adapter then
        local ok,handled=pcall(function()
            if adapter.resource and GetResourceState(adapter.resource)~='started' then return false end
            return adapter.send(d)
        end)
        if ok and handled~=false then return true end
        if Config.debug==true then print('[cdt_marketrobbery_light][debug][notifications] '..provider..' : '..tostring(ok and 'unavailable' or handled)) end
    end
    internal(d)
    return true
end
return N
