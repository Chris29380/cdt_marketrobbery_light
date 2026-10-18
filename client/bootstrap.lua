CreateThread(function()
    local Runtime=require 'shared.runtime'
    local mode
    repeat
        local ok,result=pcall(lib.callback.await,'cdt_market_light:runtimeMode',false)
        if ok and type(result)=='table' and result.apiVersion==Runtime.apiVersion and type(result.premium)=='boolean'then mode=result
        else Wait(250)end
    until mode
    local premium=mode.premium
    -- Le démarrage client du module peut suivre la réplication de quelques images.
    if premium then
        local deadline=GetGameTimer()+15000
        while GetResourceState(Runtime.module)~='started' and GetGameTimer()<deadline do Wait(50)end
        assert(Runtime.available(),'Le module Premium doit être démarré avant la Light.')
    end
    local run=Runtime.loader(premium)
    local Modules=require 'client.modules'
    Modules.bind()
    RegisterNUICallback('moduleRuntime',function(_,cb)
        cb({apiVersion=Runtime.apiVersion,premium=premium})
    end)
    if premium then run('client.police');run('client.hostages')end
    run('client.main')
    Modules.reopen()
end)
