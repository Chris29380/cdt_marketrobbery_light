-- Adaptateur des éléments requis : objets/armes d'inventaire et loadout ESX natif.
local R={}
local function copy(value)
    if type(value)~='table' then return value end
    local out={};for key,item in pairs(value)do out[key]=copy(item)end;return out
end
function R.new(bridge)
    local I={}
    local function nativeWeapon(row)
        return row.kind=='weapon' and bridge.framework=='esx' and bridge.inventory=='framework'
    end
    local function inventoryName(row)
        local name=row.name
        if row.kind=='weapon' or name:sub(1,7):lower()=='weapon_' then
            local spec=require('shared.inventories')[bridge.inventory]
            if spec and spec.weaponCase then return spec.weaponCase=='upper' and name:upper() or name:lower() end
            if bridge.inventory=='ox' then return name:upper() end
            if bridge.inventory=='qb' or bridge.inventory=='framework' and bridge.framework=='qbcore' then return name:lower() end
        end
        return name
    end
    function I.count(src,row)
        if nativeWeapon(row) then
            local player=bridge.player(src)
            return player and type(player.hasWeapon)=='function' and player.hasWeapon(row.name:upper()) and 1 or 0
        end
        local name=inventoryName(row);local count=bridge.count(src,name)
        -- Un bridge peut exposer une possession d'arme sans stock quantifié.
        -- Ce repli n'autorise jamais un retrait ou une quantité supérieure à un.
        if bridge.inventory=='custom' and count==0 and row.kind=='weapon' and row.consume=='never' and row.count==1 and type(bridge.weapon)=='function' and bridge.weapon(src,name) then return 1 end
        return count
    end
    function I.take(src,row)
        if I.count(src,row)<row.count then return false end
        if not nativeWeapon(row) then
            local name=inventoryName(row)
            if not bridge.remove(src,name,row.count) then return false end
            return true,{name=name,count=row.count}
        end
        local player=bridge.player(src);local name=row.name:upper()
        if row.count~=1 or type(player.getWeapon)~='function' or type(player.removeWeapon)~='function' or type(player.addWeapon)~='function' then return false end
        local _,weapon=player.getWeapon(name)
        if type(weapon)~='table' then return false end
        local receipt=copy(weapon);receipt.name=name;receipt.nativeWeapon=true
        if receipt.components and next(receipt.components) and type(player.addWeaponComponent)~='function' then return false end
        if receipt.tintIndex~=nil and type(player.setWeaponTint)~='function' then return false end
        player.removeWeapon(name)
        if player.hasWeapon(name) then return false end
        return true,receipt
    end
    function I.restore(src,receipt)
        if not receipt.nativeWeapon then return bridge.addItem(src,receipt.name,receipt.count) end
        local player=bridge.player(src)
        if not player or player.hasWeapon(receipt.name) then return false end
        player.addWeapon(receipt.name,receipt.ammo or 0)
        if receipt.tintIndex~=nil then player.setWeaponTint(receipt.name,receipt.tintIndex) end
        for _,component in pairs(receipt.components or {})do player.addWeaponComponent(receipt.name,component)end
        return player.hasWeapon(receipt.name)==true
    end
    return I
end
return R
