-- Bridge libre : sélectionner « Personnalisé » dans l'administration.
-- Ce fichier est chargé côté client uniquement. Aucun gain ni droit ne doit y être traité.
return {
    configured=false,
    resource=nil, -- Facultatif : nom exact de la ressource, vérifiée avant chaque notification.
    notify=function(data)
        -- data : title, message (déjà traduit), type (inform/success/error/warning),
        -- duration (millisecondes), category (message/loot/police), items (butin), location (police).
        -- Exemple : exports['mon_notify']:Show(data.message,data.type,data.duration)
        -- Retourner false si rien n'a été affiché ; nil ou true confirme la prise en charge.
        return false
    end
}
