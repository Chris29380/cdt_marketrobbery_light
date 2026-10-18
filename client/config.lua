-- Uniquement des préférences publiques. Aucun secret côté client.
Config = {
    -- Noms des mappings personnalisés, indexés par hash d’intérieur détecté.
    interiorNames = {}, -- exemple : ['123456789'] = 'Nom du mapping'
    detectSafeModels = {}, -- exemple : ['mon_modele_de_coffre'] = true
    target = false, -- false/key : prompts CDT et touche E ; auto | ox | qb pour activer un target
    notifications = 'cdt', -- Défaut interne. Choix synchronisé depuis l'administration ; bridge : client/notifications_custom.lua
    targetKeyLabel = 'ALT', -- libellé du raccourci de votre target, s'il est activé
    notificationDuration = 5000,
    -- Bases d'images facultatives pour les inventaires externes. Exemple :
    -- inventoryImagePaths = { qs = 'nui://qs-inventory/html/images' },
    inventoryImagePaths = {},
    policeAlertRadius = 50.0, -- rayon du cercle clignotant sur la carte, en mètres
    policeAlertDuration = 90 -- durée du dispatch et du signalement sur la carte, en secondes
}
