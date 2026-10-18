-- API serveur documentées ; aucun transfert de coffre n'est délégué au client.
local Specs=require 'shared.inventories'
local A={}
local methods={
    qs={count='GetItemTotalAmount',carry='CanCarryItem',add='AddItem',remove='RemoveItem'},
    origen={count='getItemCount',carry='canCarryItem',add='addItem',remove='removeItem'},
    core={count='getItemCount',carry='canCarry',add='addItem',remove='removeItem'},
    tgiann={count='GetItemCount',carry='CanCarryItem',add='AddItem',remove='RemoveItem'},
    jaksam={count='getTotalItemAmount',carry='canCarryItem',add='addItem',remove='removeItem'}
}
function A.supports(name)return methods[name]~=nil end
function A.build(name)
    local m=assert(methods[name]);local resource=Specs[name].resource
    local function invoke(method,...)
        local proxy=exports[resource];return proxy[method](proxy,...)
    end
    local function count(src,item)
        -- Jaksam : ne pas compter les sacs imbriqués que removeItem ne retire pas.
        local value=name=='jaksam' and invoke(m.count,src,item,nil,true) or invoke(m.count,src,item)
        assert(type(value)=='number' and value>=0 and value<math.huge and value%1==0,'Invalid inventory count')
        return value
    end
    local function mutate(method,src,item,amount)
        local before=count(src,item)
        local result=invoke(method,src,item,amount)
        -- Les versions sans retour explicite ne sont acceptées qu'après vérification
        -- de la quantité réellement ajoutée/retirée. Ne jamais rejouer une mutation.
        local after=count(src,item)
        return result~=false and after==before+(method==m.add and amount or -amount)
    end
    return {configured=true,resource=resource,count=count,
        canCarry=function(src,item,amount)return invoke(m.carry,src,item,amount)==true end,
        add=function(src,item,amount)
            if invoke(m.carry,src,item,amount)~=true then return false end
            return mutate(m.add,src,item,amount)
        end,
        remove=function(src,item,amount)
            -- Core retire uniquement la première pile : refuser avant toute mutation
            -- si elle ne suffit pas, au lieu de perdre une partie des prérequis.
            if name=='core' then
                local first=invoke('getItem',src,item)
                if not first or (first.amount or 0)<amount then return false end
            end
            return mutate(m.remove,src,item,amount)
        end}
end
return A
