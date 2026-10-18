# CDT Market Robbery Light — Technical notes

[Français](TECHNICAL.fr.md) · **English** · [README](../README.md)

## Optional Premium module

Since Light 1.1.0, a single optional module, `cdt_marketrobbery_premium`, can add hostages, investigations and advanced settings. Since Light 1.2.0, it can also be activated through the interface. Light works on its own without this folder. Existing rewards, timers and stores are preserved.

To enable the module, place its folder next to Light and start it first:

```cfg
ensure cdt_marketrobbery_premium
ensure cdt_marketrobbery_light
```

If Light is already running, start the module, open `/marketlightadmin`, click **Detect modules**, then **Activate module now**. The list shows whether the module is missing, stopped, incompatible, ready to activate or already active. Activation briefly reloads Light for all players and automatically reopens the requesting administrator's configuration. Premium 1.1.0 or newer is required for this reload.

Save changes before activation. Robberies and police interventions must be finished, and other administrators must close their editors to protect unsaved drafts. Activation blocks new scenes until the restart completes.

To disable the module, stop Light, stop Premium, then restart Light alone. Premium settings remain in the database and return when the module is reactivated; changes made in Light remain applied. Deleted entries are not recreated.

The mode is initialized at startup and can be updated through the activation button. No file replacement is needed for subsequent activations. Detailed module instructions are provided in its own README.

Light is free and standalone: convenience store robberies, intimidation, animated registers, cash bags, mechanical safe dials and shared loot inventory. Interfaces and notifications are available in French and English.

## In-game configuration

Administrator command: `/marketlightadmin`.

The visual editor lets administrators create, edit and delete stores; position shopkeepers, registers, bags and safes; and select safes already present in the map.

**Rewards and timers remain configurable:**

- Minimum/maximum register rewards and register duration, globally, per store and per register.
- Safe loot contents and minimum/maximum quantities.
- Store cooldown, global delay between robberies, maximum robbery duration, abandonment delay, intimidation duration and police alert delay.
- Required police count, whether registers must be emptied before safes, and four safe dial difficulty levels.

Administration includes language, framework, standard inventory, police alert jobs and notification settings.

Hostages and investigations (statements, inspections and police reopening) are not included in standalone Light. Stores become available automatically after their cooldown. Advanced weapon and item requirements, custom inventory exports in the editor, microphone features, decorative props, fine animation settings and custom difficulty require Premium. Required technical values use the built-in settings.

Duplicate payout protection, loot reservations, resuming interrupted register work and notifications with item images and quantities remain included.

## Installation

Place the `cdt_marketrobbery_light` folder in `resources/[cdt]`. Dependencies: `ox_lib`, `oxmysql`, OneSync and Qbox, QBCore or ESX. Supported inventories: Ox, QB, Quasar, Origen, Core, TGIANN, Jaksam or the framework inventory. Qbox requires a supported inventory rather than the framework fallback.

In `server.cfg`:

```cfg
set cdt_language "en"
ensure oxmysql
ensure ox_lib
# Start your framework and inventory before this resource.
ensure cdt_marketrobbery_light
add_ace group.admin cdt.market.light.admin allow
```

Use `"fr"` for French. An explicit convar sets the startup language; the editor can change it live until the next restart. Configured administrator groups are also recognized.

Events use `cdt_market_light:*`, and storage uses the `cdt_marketrobbery_light_data` SQL table. No saved data from the older full resource is copied. Do not enable both resources on the same stores: each would spawn its own shopkeepers and interactions.

Additional administrator commands: `/marketlightreset <id>` and `/marketlightminigame [easy|normal|hard|expert]` to test the dial without rewards.

## Notifications and custom bridge

The internal CDT system (`notifications = 'cdt'`) is the default. Select another provider under **Administration → Interactions and notifications**, then save. Regular messages, loot notifications and police alerts share the same bridge. Police map markers remain independent of the notification provider.

Adapters: CDT, ox_lib, okokNotify, Wasabi Notify, Brutal Notify, Mythic Notify, Quasar Interface, QBCore Notify and ESX Notify. These integrations use the providers' published APIs. Start the selected resource before Light. Types and durations are adapted: Mythic uses inform for warnings, and QBCore uses primary. External providers show loot as item names and quantities in text; internal CDT loot cards retain their images.

If a resource is stopped, an export raises an error or the custom bridge returns false, CDT takes over. Disabling notifications hides player messages, but administrator errors remain visible through CDT. Adapter failure diagnostics are printed only when administrator debug is enabled.

To connect your own notification system, edit **client/notifications_custom.lua**, set configured to true, then select **Custom** in administration:

```lua
return {
    configured = true,
    resource = 'my_notify',
    notify = function(data)
        exports['my_notify']:Show(data.message, data.type, data.duration)
        return true
    end
}
```

Adapt Show and its arguments to your actual export. The bridge receives title, an already translated message, type (inform/success/error/warning), duration in milliseconds, category (message/loot/police), items for loot and location for police alerts. Return false if nothing was displayed; nil or true confirms handling. The resource field is optional but recommended. Restart Light after editing the file.

API references: [okokNotify](https://docs.okokscripts.io/scripts/okoknotify), [Wasabi](https://docs.wasabiscripts.com/wasabi-scripts/core-ui-series/wasabi_notify/exports-events), [Brutal](https://docs.brutalscripts.com/site/scripts/notify/exports-triggers), [Mythic](https://github.com/JayMontana36/mythic_notify), [Quasar Interface](https://www.quasar-store.com/docs/interface/integrations).

## Framework and inventory compatibility

ESX, QBCore and Qbox use their player, job and account APIs. Safes are shared stock managed by Light rather than external stashes. Inventory APIs run on the server for requirements, consumption, capacity checks and safe/bag rewards. Rewards of kind money use the framework; cash maps to money on ESX. A reward of kind item named cash remains an item. With ESX/Ox, an account synchronized as an item is also subject to capacity checks, and its credit is verified after payment.

Select the inventory under **Administration → Framework and inventory**:

| Selection | Resource | Server API |
| --- | --- | --- |
| Ox | ox_inventory | Search, CanCarryItem, AddItem, RemoveItem |
| QB | qb-inventory | GetItemCount (all stacks), CanAddItem, AddItem, RemoveItem |
| Quasar | qs-inventory | GetItemTotalAmount, CanCarryItem, AddItem, RemoveItem |
| Origen | origen_inventory | getItemCount, canCarryItem, addItem, removeItem |
| Core | core_inventory | getItemCount, canCarry, addItem, removeItem |
| TGIANN | tgiann-inventory | GetItemCount, CanCarryItem, AddItem, RemoveItem |
| Jaksam | jaksam_inventory | getTotalItemAmount (excluding containers), canCarryItem, addItem, removeItem |
| Framework | es_extended / qb-core | ESX xPlayer or QBCore Functions |

Automatic detection rejects multiple active inventories: select the one you use explicitly. Commercial resources must expose the documented APIs; older versions with different APIs require a custom bridge. Custom inventory configuration is a Premium option. No QB/Ox resource aliases are required for the additional adapters. Framework and inventory versions must themselves be compatible.

Changes made through the additional adapters are confirmed by the actual stock difference, even when an export returns no value. Additions are never retried after an uncertain result. Core removes items from the first stack only: the script refuses before modifying stock if that stack is insufficient; combine required items into a sufficiently large stack. Jaksam excludes items inside nested containers when counting requirements. On TGIANN, disable createDropWhenPlayerFull to prevent ground drops if capacity changes during the operation.

Ox/QB images keep their native resolution. Quasar and Core catalogs also provide labels. For external inventory images, set Config.inventoryImagePaths in **client/config.lua** to the actual image path, for example `qs = 'nui://qs-inventory/html/images'`. Local fallback icons remain available without a configured path.

Development tests simulate 15 ESX/QBCore/Qbox combinations with the five additional adapters, including capacity checks, stopped resources, refusals, missing return values and rewards. They do not certify commercial resources in game. Test full inventories (slots and weight), money accounts, weapons, images and two players collecting the same loot batch simultaneously on your server. These Light adapters do not require changes to Premium-specific files.

References: [QB](https://qbcore.org/docs/qbcore-resources/qb-inventory), [Ox](https://github.com/overextended/ox_inventory/blob/main/modules/inventory/server.lua), [Quasar](https://www.quasar-store.com/docs/inventory/commands-and-exports), [Origen](https://docs.origennetwork.com/scripts/origen_inventory/exports), [Core](https://docs.c8re.store/core-inventory/exports), [TGIANN](https://tgiann.gitbook.io/tgiann/scripts/tgiann-inventory/exports/server), [Jaksam](https://documentation.jaksam-scripts.com/jaksam-inventory/functions/server).

## Support and Premium information

**[Join our Discord for support and information about the Premium module](https://discord.gg/yNkYVhNCQQ)**
