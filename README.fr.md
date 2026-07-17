# EbonBuilds

[English](README.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | **[Français](README.fr.md)** | [Polski](README.pl.md)

Un addon World of Warcraft (3.3.5a) pour **ProjectEbonhold** qui automatise les choix d'écho (Banish / Reroll / Freeze / Select) en fonction d'un build que vous définissez, et qui s'auto-ajuste au fil du temps à partir de données de jeu réelles.

Nécessite **ProjectEbonhold** ou **ProjectEbonhold Enhanced**. Certaines fonctionnalités utilisent en plus **[Details!](https://www.curseforge.com/wow/addons/details)** si installé.

## Ce qu'il fait

- **Définir un build** : poids par écho, bonus de qualité/famille/nouveauté, emplacements verrouillés, échos bannis.
- **Automatisation** : évalue chaque écran de choix d'écho par rapport à votre build et agit (banish/reroll/freeze/select) à votre place.
- **Tuning Advisor** : compare vos seuils de Banish/Reroll/Freeze à ce que votre build reçoit réellement en offre (pas un modèle théorique), suggère de meilleures valeurs et peut les ajuster automatiquement et progressivement au fil du temps.
- **Répartition du budget sur toute la run** : les seuils deviennent automatiquement plus stricts à mesure que les charges de Banish/Reroll/Freeze diminuent, pour éviter de gaspiller vos dernières charges sur des offres limites.
- **Suivi du DPS et du taux d'apparition** : avec Details! installé, suit le DPS réel par écho actif ; suit toujours la fréquence à laquelle chaque écho apparaît réellement sur un écran de choix. Les deux peuvent être synchronisés en option avec d'autres joueurs de la même classe.
- **Manual Training Mode** : suspendez l'automatisation d'un build, choisissez manuellement, et EbonBuilds apprend de vos choix, générant des suggestions de poids à partir de ce que vous avez réellement préféré.
- **Suggestions de poids et de bonus** : les données de DPS et les choix manuels alimentent tous deux des suggestions de poids par écho, ainsi que (de façon expérimentale) des suggestions de bonus de Qualité/Famille.
- **Export (AI)** : un export complet en texte brut des paramètres du build, de tous les échos disponibles pour votre classe avec de vraies descriptions d'effet, et de toutes les données de réglage — destiné à être collé dans un chat IA pour analyse.
- **Tome Atlas** : emplacements de drop des tomes d'écho, recueillis par la communauté.
- **Public Builds** : parcourez et importez des builds partagés par d'autres joueurs.

Voir [`FAQ.md`](FAQ.md) pour des explications détaillées de chaque fonctionnalité, et [`CHANGELOG.md`](CHANGELOG.md) pour l'historique complet des versions.

## Installation

La racine de ce dépôt *est* le dossier de l'addon (`EbonBuilds.toc`, `core/`, `modules/` se trouvent au niveau supérieur, pas dans un sous-dossier).

**Via Git :**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Via téléchargement ZIP :** le bouton « Download ZIP » de GitHub nomme le dossier extrait d'après la branche (ex. `EbonBuilds-main`) — renommez-le exactement en `EbonBuilds` avant de le placer dans `Interface/AddOns/`, pour que le nom du dossier corresponde à `EbonBuilds.toc`.

Puis redémarrez le jeu ou faites `/reload`.

## Commandes

Chaque commande commence par `/ebb`. Une référence complète est aussi disponible en jeu via `/ebb showcase`.

| Commande | Description |
|---|---|
| `/ebb` | Ouvrir ou fermer la fenêtre principale |
| `/ebb faq` (ou `/ebb help`) | Guide complet en jeu |
| `/ebb showcase` (ou `/ebb commands`) | Cette liste de commandes, en jeu |
| `/ebb tuning` (ou `/ebb advisor`) | Tuning Advisor : seuils, auto-tune, partage DPS/taux d'apparition |
| `/ebb cleartraining` | Effacer les données de Manual Training du build actif |
| `/ebb atlas` (ou `/ebb tomes`) | Tome Atlas |
| `/ebb affix` | Référence des affixes |
| `/ebb autosell` | Activer/désactiver la vente automatique des objets à 0 cuivre chez les marchands |
| `/ebb bagdots` | Activer/désactiver les points colorés sur les objets du sac sans affixe |
| `/ebb debug` | Activer/désactiver la journalisation détaillée des décisions de l'automatisation |
| `/ebb debuglog` (ou `/ebb log`) | Voir le journal de débogage capturé |
| `/ebb errors` | Voir les erreurs capturées, pour les rapports de bugs |
| `/ebb clicktrace` | Journaliser chaque clic de bouton de l'interface, pour les rapports « rien ne s'est passé » |

## Signaler un bug

Joignez la sortie de `/ebb errors` ou un journal `/ebb debug` à votre rapport — c'est le moyen le plus rapide d'obtenir une vraie correction plutôt qu'une supposition.

## Développement

- Lua pur, API WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` est utilisé pour vérifier la syntaxe de chaque fichier avant chaque version ; voir `.github/workflows/lua-syntax.yml` pour la même vérification exécutée en CI.
- Aucune étape de build — la racine du dépôt *est* la structure de dossier de l'addon attendue par `Interface/AddOns/`.
