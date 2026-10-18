-- Réaction locale reconstruite depuis l'état partagé du magasin.
MarketClerk={}
local M=MarketClerk
local reacting={}
local dict,clip='random@mugging3','handsup_standing_base'
function M.clear(ped)
    if not reacting[ped] then return end
    if DoesEntityExist(ped) then
        StopAnimTask(ped,dict,clip,-4.0)
        ClearFacialIdleAnimOverride(ped)
    end
    reacting[ped]=nil
end
function M.update(ped,state)
    if not ped or not DoesEntityExist(ped) then return end
    for _,activity in pairs(state and state.activities or {}) do
        if activity.stage=='register' then M.clear(ped);return end
    end
    local afraid=state and not state.clerkCalm and (state.phase=='intimidating' or state.phase=='active')
    if not afraid then M.clear(ped);return end
    if not reacting[ped] then
        SetFacialIdleAnimOverride(ped,'mood_scared_1',0)
        reacting[ped]=true
    end
    if not IsEntityPlayingAnim(ped,dict,clip,3) then
        if not HasAnimDictLoaded(dict) then RequestAnimDict(dict);return end
        -- Boucle de reddition ; le ped reste à son emplacement au sol.
        TaskPlayAnim(ped,dict,clip,4.0,-4.0,-1,49,0,false,false,false)
    end
end
