fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'cdt_marketrobbery_light'
author 'CDTFiveM'
description 'Version gratuite : caisses, sacs, coffres et configuration en jeu'
version '1.2.0'
shared_scripts { '@ox_lib/init.lua' }
client_scripts { 'client/config.lua', 'client/registers.lua', 'client/ground.lua', 'client/admin.lua', 'client/clerk.lua', 'client/safes.lua', 'client/bootstrap.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'config.lua', 'server/bootstrap.lua' }
ui_page 'nui/index.html'
files { 'shared/inventories.lua', 'shared/notifications.lua', 'client/notifications.lua', 'client/notifications_custom.lua', 'client/modules.lua', 'shared/runtime.lua', 'client/main.lua', 'nui/free.html', 'nui/branding.js', 'nui/branding.css', 'nui/safe_theme.css', 'nui/acstudio-logo.png', 'nui/frame_ready.js', 'nui/module_host.js', 'nui/index.html', 'nui/style.css', 'nui/instruments.css', 'nui/drill.css', 'nui/overlays.css', 'nui/app.js', 'nui/inventory.js', 'nui/overlays.js', 'nui/localization.js', 'nui/models/*.webp', 'locales/*.json', 'shared/locale.lua', 'shared/registers.lua', 'shared/presentation.lua', 'shared/loot.lua', 'shared/safes.lua', 'client/debug_minigames.lua', 'client/inventory.lua', 'nui/config_cards.js', 'nui/config_cards.css', 'nui/illustrations/*.svg' }
dependencies { 'oxmysql', 'ox_lib', '/onesync' }
