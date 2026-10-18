-- Lots tirés une seule fois, puis réservés et payés individuellement.
local L={}
function L.viewable(state,id)
    local stock=state and state.safes and state.safes[id]
    return state and (state.phase=='active' or state.phase=='cooldown') and stock and stock.openedAt
        and (stock.status=='open' or stock.status=='looted') or false
end
function L.collectable(state,id)
    return L.viewable(state,id) and state.phase=='active' and state.safes[id].status=='open'
end
function L.prepare(rewards,models)
    local chunks={}
    for _,reward in ipairs(rewards) do
        local count=math.min(reward.amount,reward.kind=='money' and 6 or 3,math.max(1,math.floor(36/math.max(1,#rewards))))
        local base=math.floor(reward.amount/count)
        for index=1,count do
            local amount=base+(index<=reward.amount%count and 1 or 0)
            chunks[#chunks+1]={id='lot_'..(#chunks+1),kind=reward.kind,name=reward.name,amount=amount,initialAmount=amount,
                model=reward.model or models[reward.name] or (reward.kind=='money' and 'hei_prop_heist_cash_pile' or 'prop_cs_cardbox_01'),
                label=reward.label or reward.name,status='ready'}
        end
    end
    return chunks
end
function L.find(safe,id)
    for _,chunk in ipairs(safe.chunks or {}) do if chunk.id==id then return chunk end end
end
function L.empty(safe)
    for _,chunk in ipairs(safe.chunks or {}) do if chunk.status~='taken' then return false end end
    return true
end
return L
