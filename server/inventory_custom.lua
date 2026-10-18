-- Adaptateur serveur pour un inventaire personnalisé.
-- Sélectionner Config.inventory='custom' dans config.lua.
-- Implémenter les quatre fonctions puis passer configured à true.
-- Aucun événement client : les droits et les paiements restent côté serveur.
return {
    configured = false,
    resource = nil, -- nom de votre ressource (facultatif, vérifié au démarrage)

    -- Quantité TOTALE de cet objet, tous emplacements confondus.
    -- Retour : entier positif ou nul ; conserver la casse attendue par l'inventaire.
    count = function(source, item)
        error('Implémenter count dans server/inventory_custom.lua')
    end,

    -- Retour : true uniquement si toute la quantité peut être portée.
    -- Ne rien ajouter ici : ce contrôle ne doit pas modifier l'inventaire.
    canCarry = function(source, item, amount)
        error('Implémenter canCarry dans server/inventory_custom.lua')
    end,

    -- Retour : true uniquement après ajout effectif de TOUTE la quantité.
    -- Retourner false en cas de refus ; ne pas déposer les objets au sol.
    add = function(source, item, amount)
        error('Implémenter add dans server/inventory_custom.lua')
    end,

    -- Retour : true uniquement après retrait effectif de TOUTE la quantité.
    remove = function(source, item, amount)
        error('Implémenter remove dans server/inventory_custom.lua')
    end,

    -- Facultatif : hasWeapon = function(source, weaponName) return boolean end
    -- Si absent, la recherche utilise count(source, weaponName:lower()).
}
