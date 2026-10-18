local Runtime=require 'shared.runtime'
local M={}
function M.new(ctx)
    local self={reloading=false,editors={}}
    function self.open(src)self.editors[src]=true end
    function self.close(src)self.editors[src]=nil end
    local function reason(src)
        if self.reloading then return 'Activation du module en cours. Patientez un instant.' end
        if ctx.active()then return 'Terminez les braquages et les interventions avant d’activer le module.' end
        for player in pairs(self.editors)do
            if player~=src then return 'Un autre administrateur utilise la configuration. Demandez-lui de fermer son interface.'end
        end
    end
    local function scan(src)
        local state=type(GetResourceState)=='function' and GetResourceState(Runtime.module)or 'missing'
        local ok,compatible=pcall(Runtime.available)
        compatible=ok and compatible==true
        local loaded=GlobalState and GlobalState.cdtMarketRobberyRuntime=='premium'
        local label
        if loaded and state=='started' then label='Actif'
        elseif state=='started' and compatible then label='Démarré, prêt à activer'
        elseif state=='started' then label='Version incompatible'
        elseif state=='missing' then label='Non installé'
        else label='Arrêté'end
        local why=reason(src)
        if not why then
            if loaded then why='Le module est déjà actif.'
            elseif state~='started' then why='Démarrez cdt_marketrobbery_premium sur le serveur, puis relancez la détection.'
            elseif not compatible then why='Mettez à jour le module Premium et la Light avec des versions compatibles.'end
        end
        return {modules={{id=Runtime.module,name='CDT Market Robbery Premium',state=state,compatible=compatible,active=loaded==true,label=label}},canApply=not loaded and compatible and not why,reason=why}
    end
    ctx.callback('modulesStatus',function(src)
        if not ctx.admin(src)then return {error='Accès administrateur refusé.'}end
        return scan(src)
    end)
    ctx.callback('applyModules',function(src)
        if not ctx.admin(src)then return {error='Accès administrateur refusé.'}end
        local result=scan(src)
        if not result.canApply then return {error=result.reason or 'Aucun module à activer.'}end
        self.reloading=true
        local ok,accepted=pcall(function()return exports[Runtime.module]:reloadCore()end)
        if not ok or accepted~=true then
            self.reloading=false
            return {error='La recharge n’a pas pu démarrer. Vérifiez que le module Premium est à jour et démarré.'}
        end
        TriggerClientEvent('cdt_market_light:moduleReload',src,true)
        SetTimeout(15000,function()
            -- Cette fonction disparaît si le noyau a redémarré normalement.
            self.reloading=false
            TriggerClientEvent('cdt_market_light:moduleReload',src,false)
            ctx.notify(src,'L’activation n’a pas abouti. Relancez la détection des modules.','error')
        end)
        return {ok=true,reloading=true}
    end)
    if type(RegisterNetEvent)=='function'then RegisterNetEvent('cdt_market_light:editorClosed')end
    AddEventHandler('cdt_market_light:editorClosed',function()self.close(source)end)
    AddEventHandler('playerDropped',function()self.close(source)end)
    return self
end
return M
