local P={}
local Loot=require 'shared.loot'
function P.robberyAllowed(config,permissions)
    return config.policeCanRob~=false or permissions and permissions.canRob==true or false
end
function P.notification(message)
    local text=tostring(message)
    local lower=text:lower()
    local messages={
        ['Inventaire plein ou récompense indisponible. Libère de la place puis réessaie.']='Vous ne pouvez pas emporter ce butin. Faites de la place sur vous puis réessayez.',
        ['Inventaire plein. Libère de la place puis réessaie.']='Vous n’avez plus assez de place sur vous. Allégez-vous avant de prendre le sac.',
        ['Attribution impossible. Point verrouillé ; un administrateur peut consulter le journal et régulariser.']='Vous ne parvenez pas à récupérer ce butin.',
        ['Attribution impossible. Consulter un administrateur.']='Vous ne parvenez pas à récupérer le contenu du sac.',
        ['Ce lot est indisponible.']='Quelqu’un est déjà en train de prendre ce butin, ou il n’y a plus rien à cet endroit.',
        ['Lot expiré.']='Ce butin n’est plus à portée de main.',
        ['Récupération indisponible.']='Vous ne pouvez pas saisir ce butin pour le moment.',
        ['Ce coffre est uniquement consultable.']='Vous pouvez regarder dans ce coffre, mais vous ne pouvez plus emporter son contenu.',
        ['Inventaire fermé.']='Vous avez cessé de fouiller le coffre.',
        ['Récupération interrompue.']='Vous avez interrompu la fouille du coffre.',
        ['Sac indisponible ou trop éloigné.']='Approchez-vous du sac pour le ramasser. Il a peut-être déjà été pris.',
        ['Caisse occupée ou déjà vidée.']='Le commerçant s’occupe déjà de cette caisse, ou elle est vide.',
        ['Coffre indisponible pour le moment.']='Vous ne pouvez pas forcer ce coffre pour le moment.',
        ['Nombre de tentatives épuisé pour ce coffre.']='Vous avez trop forcé sur le mécanisme. La serrure ne cède plus.',
        ['Action déjà en cours.']='Terminez ce que vous faites avant de recommencer.',
        ['Une demande est déjà en cours.']='Un instant, vous n’avez pas encore terminé votre geste.',
        ['Patiente un instant.']='Prenez votre temps avant de recommencer.',
        ['Délai global de braquage actif.']='Faites-vous oublier avant de tenter un autre braquage.',
        ['Ce magasin est occupé ou en recharge.']='Le commerçant ne peut pas coopérer pour le moment.',
        ['Trop de braquages simultanés.']='Le quartier est déjà trop agité. Attendez que la situation se calme.',
        ['Pas assez de policiers en service.']='Il n’y a pas assez de patrouilles en ville pour tenter le coup.',
        ['Action trop rapide.']='Vous n’avez pas encore terminé votre geste.',
        ['Mesure trop rapide.']='Prenez votre temps pour manipuler le mécanisme.',
        ['Conditions de fin non remplies.']='Vous n’avez plus le nécessaire à portée de main pour continuer.',
        ['Objet requis indisponible.']='Il vous manque le nécessaire pour continuer.',
        ['Impossible de consommer les objets.']='Vous ne parvenez pas à utiliser votre matériel.',
        ['Impossible de préparer le sac.']='Le commerçant n’arrive pas à préparer le sac pour le moment.',
        ['Le coffre ou ses animations ne sont pas disponibles.']='Vous ne parvenez pas à saisir le contenu du coffre.',
        ['Action expirée.']='Vous avez attendu trop longtemps pour poursuivre.',
        ['Tentative expirée.']='Vous avez attendu trop longtemps pour continuer à forcer la serrure.',
        ['Gestion des otages indisponible.']='Vous n’arrivez pas à vous faire entendre pour le moment.',
        ['Otage indisponible ou ordre périmé.']='Cette personne ne peut plus suivre cet ordre. Rapprochez-vous d’elle.',
        ['Transfert expiré ou indisponible.']='Votre complice n’est plus en mesure de prendre le relais.',
        ['Point de sécurité absent.']='Vous ne trouvez pas d’endroit sûr où conduire cette personne.',
        ['Le commerçant refuse et déclenche l’alarme. Le magasin passe en recharge.']='Le commerçant refuse de coopérer et déclenche l’alarme. Il ne cédera plus pour le moment.'
    }
    if messages[text] then return messages[text] end
    for _,word in ipairs({'sql','console','journal','administr','ressource','sauvegarde','modèle','model','prévisual','animation','token','serveur','bridge','export','script','staff','synchron','requête','configuration','interne'}) do
        if lower:find(word,1,true) then return 'Vous n’arrivez pas à poursuivre pour le moment. Réessayez dans un instant.' end
    end
    return text
end
function P.streamRadius(store) return math.max(65,(store.radius or 0)+25) end
function P.target(config,state)
    local requested=config.target
    if requested=='auto' then
        if state('ox_target')=='started' then return 'ox' end
        if state('qb-target')=='started' then return 'qb' end
        return 'key'
    end
    if requested=='ox' and state('ox_target')=='started' then return 'ox' end
    if requested=='qb' and state('qb-target')=='started' then return 'qb' end
    return 'key'
end
-- Un point proche peut sortir du champ, notamment en vue à la première personne.
function P.promptPosition(visible,x,y)
    if visible and type(x)=='number' and type(y)=='number' and x>0 and x<1 and y>0 and y<1 then return x,y end
    return 0.5,0.78
end
function P.available(state,stage,point,safe,now,globalUntil,chunkId)
    if not state then return false end
    if stage=='intimidate' then return state.phase=='available' and now>=(globalUntil or 0) end
    if stage=='collect' then
        if not chunkId then return Loot.viewable(state,point) end
        if not Loot.collectable(state,point) then return false end
        for _,chunk in ipairs(state.safes[point].chunks or {})do if chunk.id==chunkId and chunk.status=='ready'then return true end end
        return false
    end
    if state.phase~='active' then return false end
    if stage=='register' then
        for _,activity in pairs(state.activities or {}) do if activity.stage=='register' then return false end end
        if point then return state.registers[point]=='ready' end
        for _,status in pairs(state.registers) do if status=='ready' then return true end end
        return false
    end
    if stage~='safe' or not safe then return false end
    local s=state.safes[point]
    if not s or s.status~='ready' or (s.retryAt or 0)>now or (safe.attemptLimit and s.failures>=safe.attemptLimit) then return false end
    if safe.requiresRegisters then for _, status in pairs(state.registers) do if status~='looted' then return false end end end
    return true
end
return P
