local A={}
local InventoryConfigured=require 'server.inventory_configured'
local Locale=require 'shared.locale'
local defaults={framework='auto',inventory='auto',debug=false,lootGrabDuration=3,policeJobs={police=true,sheriff=true},adminGroups={admin=true,owner=true,superadmin=true,god=true},target=false,notifications='cdt',notificationDuration=5000,policeAlertRadius=50,policeAlertDuration=90}
defaults.inventoryCustom=InventoryConfigured.defaults()
defaults.language=Locale.defaultLanguage('fr')
defaults.policeCanRob=true
local function copy(v)if type(v)~='table' then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
function A.current(config)
    local out={};for key,value in pairs(defaults)do out[key]=copy(config[key]);if out[key]==nil then out[key]=copy(value)end end
    if config.language==nil then out.language=Locale.defaultLanguage(defaults.language) end
    return out
end
function A.apply(config,settings)for key in pairs(defaults)do config[key]=copy(settings[key])end end
function A.preferences(config)
    local out={};for _,key in ipairs({'debug','target','notifications','notificationDuration','policeAlertRadius','policeAlertDuration','policeCanRob'})do out[key]=config[key];if out[key]==nil then out[key]=defaults[key]end end;out.localization=Locale.bundle(config.language or Locale.defaultLanguage(defaults.language));return out
end
function A.validate(s)
    if type(s)~='table' then return false,'Réglages administratifs invalides.' end
    if s.policeCanRob==nil then s.policeCanRob=true end
    if s.language==nil then s.language=Locale.defaultLanguage(defaults.language) end
    if type(s.language)~='string' or not Locale.available()[s.language] then return false,'Langue indisponible.' end
    -- Les sauvegardes antérieures au formulaire des exports restent lisibles.
    if s.inventoryCustom==nil then s.inventoryCustom=InventoryConfigured.defaults()end
    local valid,why=InventoryConfigured.validate(s.inventoryCustom);if not valid then return false,why end
    for key in pairs(s)do if defaults[key]==nil then return false,'Paramètre administratif inconnu.'end end
    if not ({auto=true,esx=true,qbcore=true,qbox=true})[s.framework] or not (s.inventory=='auto' or require('shared.inventories')[s.inventory])then return false,'Bridge inconnu.'end
    if s.target~=false and not ({key=true,auto=true,ox=true,qb=true})[s.target]then return false,'Interaction inconnue.'end
    if s.notifications~=false and not require('shared.notifications')[s.notifications] then return false,'Notifications invalides.'end
    for _,key in ipairs({'debug','policeCanRob'})do if type(s[key])~='boolean'then return false,'Option invalide : '..key end end
    local function number(v,min,max)return type(v)=='number' and v==v and v>=min and v<=max and v%1==0 end
    for key,range in pairs({lootGrabDuration={1,60},notificationDuration={1500,15000},policeAlertRadius={5,500},policeAlertDuration={5,600}})do if not number(s[key],range[1],range[2])then return false,'Valeur invalide : '..key end end
    for _,key in ipairs({'policeJobs','adminGroups'})do
        if type(s[key])~='table'then return false,'Liste de permissions invalide.'end
        local count=0;for name,value in pairs(s[key])do count=count+1;if type(name)~='string' or #name<1 or #name>64 or not name:match('^[%w_%-]+$')or value~=true or count>32 then return false,'Groupe ou métier invalide.'end end
        if count==0 then return false,'Conservez au moins un groupe ou métier.'end
    end
    if not s.adminGroups.admin or not s.adminGroups.owner then return false,'Les groupes admin et owner doivent conserver leur accès.'end
    return true
end
return A
