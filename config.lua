Config = {
    notifications = 'cdt', -- Défaut interne ; sélection des autres systèmes dans l'administration.
    language = 'fr', -- Repli si cdt_language est absent du server.cfg ; fr ou en.
    framework = 'auto', -- auto | qbox | qbcore | esx
    inventory = 'auto', -- auto | ox | qb | qs | origen | core | tgiann | jaksam | framework | custom (server/inventory_custom.lua)
    adminAce = 'cdt.market.light.admin',
    policeAce = 'cdt.market.light.police', -- Permission des interventions du module Premium.
    adminGroups = { admin = true, owner = true, superadmin = true, god = true },
    policeJobs = { police = true, sheriff = true },
    policeCanRob = true, -- false : ces métiers ne peuvent pas braquer, même hors service
    lootGrabDuration = 3,
    lootProps = { gold='prop_gold_bar', goldbar='prop_gold_bar', phone='prop_phone_ing', laptop='prop_laptop_01a' },
    defaults = {
        minPolice = 0, cooldown = 1800, globalCooldown = 120,
        maxDuration = 900, abandonDelay = 120, maxActive = 3,
        alertChance = 100, alertDelay = 5, refusalChance = 0,
        intimidateDuration = 4, registerDuration = 12,
        safeSteps = 3, safeTolerance = 7, safeDuration = 90,
        safeAttempts = 3, safePenalty = 20,
        requirements = {
            intimidate = { weaponMode = 'any', weapons = { 'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_SNSPISTOL', 'WEAPON_KNIFE' }, equipped = true, itemMode = 'all', items = {} },
            register = { weaponMode = 'any', weapons = {}, equipped = false, itemMode = 'all', items = {} },
            safe = { weaponMode = 'any', weapons = {}, equipped = false, itemMode = 'all', items = {} }
        },
        registerReward = { kind = 'money', name = 'cash', min = 100, max = 350 },
        safeReward = { kind = 'money', name = 'cash', min = 500, max = 1200 },
        safeRequiresRegisters = true
    },
    stores = {
        {
            id = 'strawberry', label = '24/7 · Strawberry', enabled = true,
            center = { x = 28.1, y = -1345.0, z = 29.5 }, radius = 18.0,
            clerk = { model = 'mp_m_shopkeep_01', x = 24.47, y = -1346.62, z = 29.5, heading = 271.0 },
            registers = {
                { id = 'caisse_1', x = 24.95, y = -1344.97, z = 29.5 },
                { id = 'caisse_2', x = 24.95, y = -1347.3, z = 29.5 }
            },
            safes = {{ id = 'coffre', label = 'Coffre arrière', model = 'prop_ld_int_safe_01', spawnProp = false,
                x = 28.15, y = -1338.5, z = 29.5, heading = 0,
                interaction = { x = 28.15, y = -1338.5, z = 29.5 }, requiresRegisters = true,
                loot = {{ kind = 'money', name = 'cash', min = 500, max = 1200, chance = 100 }},
                minigame = { type = 'dial', difficulty = 'normal' }
            }},
            props = {}, settings = {}
        }
    }
}
