# CDT Market Robbery Light

## Module Premium facultatif

Depuis la version 1.1.0, un seul module `cdt_marketrobbery_premium` peut ajouter les otages, les enquêtes et les réglages avancés. Depuis la version 1.2.0, son activation peut aussi se faire depuis l'interface. La Light fonctionne seule sans ce dossier. Les gains, délais et supérettes existants sont conservés.

Pour activer le module, placer son dossier à côté de la Light et le démarrer avant elle :

```cfg
ensure cdt_marketrobbery_premium
ensure cdt_marketrobbery_light
```

Si la Light fonctionne déjà, démarrer le module, ouvrir `/marketlightadmin`, cliquer sur **Détecter les modules**, puis **Activer le module maintenant**. La liste indique si le module est absent, arrêté, incompatible, prêt à activer ou déjà actif. L'activation recharge brièvement la Light pour tous les joueurs et rouvre automatiquement la configuration de l'administrateur qui l'a demandée. Le module Premium doit être en version 1.1.0 ou ultérieure pour assurer cette recharge.

Les modifications doivent être enregistrées avant l'activation. Les braquages et les interventions doivent être terminés, et les autres administrateurs doivent fermer leur éditeur pour préserver leurs brouillons. Une activation en cours empêche les nouvelles scènes jusqu'au redémarrage.

Pour désactiver le module : arrêter la Light, arrêter le module, puis redémarrer la Light seule. Les paramètres Premium sont conservés en base et retrouvés à la réactivation ; les modifications gratuites restent appliquées. Les éléments supprimés ne sont pas recréés.

Le mode est initialisé au démarrage et peut être actualisé par le bouton d'activation. Aucun remplacement des fichiers n'est nécessaire lors des activations suivantes. Les consignes détaillées figurent dans le README du module.

Version gratuite et autonome : braquages de supérettes, intimidation, caisses animées, sacs d'argent, coffres au cadran mécanique et inventaire partagé du butin. Interfaces et notifications en français et en anglais.

## Configuration en jeu

Commande administrateur : `/marketlightadmin`.

L'éditeur illustré permet de créer, modifier et supprimer les supérettes, de placer les commerçants, les caisses, les sacs et les coffres, et de sélectionner les coffres présents dans le décor.

Les **gains et les délais restent configurables** :

- gains minimum/maximum et durée des caisses, globalement, par supérette et par caisse ;
- contenu et quantités minimum/maximum du butin des coffres ;
- recharge d'une supérette, délai global entre départs, durée maximale du braquage, délai d'abandon, durée d'intimidation et délai de l'alerte police ;
- quota de policiers, nécessité de vider les caisses avant les coffres et difficulté du cadran parmi quatre niveaux.

L'administration conserve le choix de la langue, du framework, de l'inventaire standard, des métiers recevant l'alerte et des notifications.

Les otages et les enquêtes (témoignages, inspections et réouverture police) sont retirés. La supérette redevient disponible automatiquement après sa recharge. Les conditions avancées d'armes et d'objets, les exports d'inventaire personnalisés dans l'éditeur, le microphone, les accessoires décoratifs, les réglages fins des animations et la difficulté personnalisée ne sont pas proposés. Les valeurs techniques nécessaires utilisent les réglages intégrés.

Les protections contre le double paiement, les réservations du butin, la reprise d'une caisse interrompue et les notifications avec image et quantité sont conservées.

## Installation

Placer le dossier `cdt_marketrobbery_light` dans `resources/[cdt]`. Dépendances : `ox_lib`, `oxmysql`, OneSync et un framework Qbox, QBCore ou ESX. Inventaires pris en charge : Ox, QB, Quasar, Origen, Core, TGIANN, Jaksam ou celui du framework.

Dans `server.cfg` :

```cfg
set cdt_language "fr"
ensure oxmysql
ensure ox_lib
# Démarrer votre framework et votre inventaire avant la ressource.
ensure cdt_marketrobbery_light
add_ace group.admin cdt.market.light.admin allow
```

Utiliser `"en"` pour l'anglais. Un convar explicite fixe la langue au démarrage ; l'éditeur peut ensuite la modifier en direct jusqu'au prochain redémarrage. Les groupes administrateurs configurés sont également reconnus.

Les événements utilisent `cdt_market_light:*`, le stockage utilise la table SQL `cdt_marketrobbery_light_data`. Aucune sauvegarde de la version complète n'est copiée. Ne pas activer les deux versions sur les mêmes supérettes : elles créeraient chacune leurs commerçants et leurs interactions.

Commandes administrateur complémentaires : `/marketlightreset <identifiant>` et `/marketlightminigame [easy|normal|hard|expert]` pour tester le cadran sans récompense.

## Notifications et bridge personnalisé

Le système interne CDT (`notifications = 'cdt'`) reste le choix par défaut. Choisir un autre fournisseur dans **Administration → Interactions et notifications**, puis enregistrer. Les messages courants, le butin et les alertes police utilisent le même bridge. Les marqueurs de police sur la carte restent indépendants du fournisseur.

Adaptateurs : CDT, ox_lib, okokNotify, Wasabi Notify, Brutal Notify, Mythic Notify, Quasar Interface, QBCore Notify et ESX Notify. Il s’agit des API publiées, pas d’un classement de ventes. Démarrer la ressource choisie avant la Light. Les types et durées sont adaptés ; Mythic affiche les avertissements en inform, QBCore en primary. Un fournisseur externe affiche le butin sous forme de texte avec noms et quantités ; les cartes CDT gardent leurs images en mode interne.

Si une ressource est arrêtée, un export lève une erreur, ou le bridge personnalisé retourne false, CDT prend le relais. Désactiver les notifications masque les messages joueur, mais les erreurs administratives restent visibles avec CDT. Les diagnostics d’échec d’adaptateur sont affichés uniquement quand le debug admin est activé.

Pour brancher son système, éditer **client/notifications_custom.lua**, passer configured à true, puis sélectionner **Personnalisé** dans l’administration :

```lua
return {
    configured = true,
    resource = 'mon_notify',
    notify = function(data)
        exports['mon_notify']:Show(data.message, data.type, data.duration)
        return true
    end
}
```

Adapter Show et ses arguments à son export réel. Le bridge reçoit title, message déjà traduit, type (inform/success/error/warning), duration en ms, category (message/loot/police), items pour le butin et location pour la police. Retourner false si rien n’a été affiché ; nil ou true confirme la prise en charge. Le champ resource est facultatif mais recommandé. Redémarrer la Light après modification du fichier.

Sources des API : [okokNotify](https://docs.okokscripts.io/scripts/okoknotify), [Wasabi](https://docs.wasabiscripts.com/wasabi-scripts/core-ui-series/wasabi_notify/exports-events), [Brutal](https://docs.brutalscripts.com/site/scripts/notify/exports-triggers), [Mythic](https://github.com/JayMontana36/mythic_notify), [Quasar Interface](https://www.quasar-store.com/docs/interface/integrations).

## Compatibilité frameworks et inventaires

ESX, QBCore et Qbox utilisent leurs API de joueurs, métiers et comptes. Le coffre est un stock partagé géré par la Light, pas un stash externe. Les API d’inventaire sont appelées côté serveur pour les prérequis, consommations, capacités et récompenses des coffres et sacs. Les gains de type money utilisent le framework ; cash est traduit en money sur ESX. Un gain de type item nommé cash reste un objet. Avec ESX/Ox, un compte synchronisé comme objet est aussi soumis au contrôle de capacité, et son crédit est confirmé après versement.

Choisir l’inventaire dans **Administration → Framework et inventaire** :

| Choix | Ressource | API serveur |
| --- | --- | --- |
| Ox | ox_inventory | Search, CanCarryItem, AddItem, RemoveItem |
| QB | qb-inventory | GetItemCount (toutes les piles), CanAddItem, AddItem, RemoveItem |
| Quasar | qs-inventory | GetItemTotalAmount, CanCarryItem, AddItem, RemoveItem |
| Origen | origen_inventory | getItemCount, canCarryItem, addItem, removeItem |
| Core | core_inventory | getItemCount, canCarry, addItem, removeItem |
| TGIANN | tgiann-inventory | GetItemCount, CanCarryItem, AddItem, RemoveItem |
| Jaksam | jaksam_inventory | getTotalItemAmount (sans conteneurs), canCarryItem, addItem, removeItem |
| Framework | es_extended / qb-core | xPlayer ESX ou Functions QBCore |

Auto refuse plusieurs inventaires simultanés : choisir explicitement celui utilisé. Les ressources commerciales doivent exposer les API documentées ; une ancienne version divergente nécessite un bridge personnalisé. Aucun alias QB/Ox n’est requis pour les nouveaux adaptateurs. Les versions des inventaires et du framework doivent elles-mêmes être compatibles entre elles.

Les mutations des nouveaux adaptateurs sont confirmées par la variation réelle du stock, même si l’export ne retourne rien. Aucun ajout n’est rejoué après un résultat incertain. Core retire depuis la première pile uniquement : le script refuse avant toute mutation si cette pile est insuffisante ; regrouper les objets requis dans une pile suffisante. Jaksam ne compte pas les objets des conteneurs imbriqués pour les prérequis. Sur TGIANN, désactiver createDropWhenPlayerFull pour éviter un dépôt au sol si la capacité change pendant l’opération.

Les images Ox/QB gardent leur résolution native. Les catalogues Quasar et Core fournissent aussi les libellés. Pour les images d’un inventaire externe, renseigner Config.inventoryImagePaths dans **client/config.lua** avec son vrai chemin, par exemple `qs = 'nui://qs-inventory/html/images'`. Sans chemin configuré, les icônes locales restent disponibles.

Les tests simulent 15 combinaisons ESX/QBCore/Qbox avec les cinq nouveaux adaptateurs, les capacités, arrêts, refus, retours sans valeur et récompenses. Ils ne certifient pas l’exécution des ressources commerciales en jeu. Tester sur le serveur : inventaire plein (slots et poids), comptes monétaires, armes, images et prise simultanée du même lot à deux joueurs. Les fichiers spécifiques du module Premium ne sont pas modifiés par cette mise à jour Light.

Références : [QB](https://qbcore.org/docs/qbcore-resources/qb-inventory), [Ox](https://github.com/overextended/ox_inventory/blob/main/modules/inventory/server.lua), [Quasar](https://www.quasar-store.com/docs/inventory/commands-and-exports), [Origen](https://docs.origennetwork.com/scripts/origen_inventory/exports), [Core](https://docs.c8re.store/core-inventory/exports), [TGIANN](https://tgiann.gitbook.io/tgiann/scripts/tgiann-inventory/exports/server), [Jaksam](https://documentation.jaksam-scripts.com/jaksam-inventory/functions/server).
