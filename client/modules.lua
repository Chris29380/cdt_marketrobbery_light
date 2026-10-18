local M={}
local key='cdt_market:reopenConfigAfterModule'
local function now()return math.floor(GetGameTimer()/1000)end
function M.bind()
    RegisterNetEvent('cdt_market_light:moduleReload',function(reloading)
        if reloading then SetResourceKvpInt(key,now()+30)
        else DeleteResourceKvp(key)end
    end)
end
function M.reopen()
    local untilTime=GetResourceKvpInt(key)
    DeleteResourceKvp(key)
    if untilTime<=now()then return end
    CreateThread(function()
        while now()<untilTime do
            Wait(800)
            local ok,result=pcall(lib.callback.await,'cdt_market_light:admin',false)
            if ok and type(result)=='table' and result.config then
                ExecuteCommand('marketlightadmin')
                return
            end
        end
    end)
end
return M
