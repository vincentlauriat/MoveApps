# Guide utilisateur

Ce guide couvre la prise en main de MoveApps.app une fois installée (voir `README.md` pour l'installation). Pour la note de confidentialité, voir `PRIVACY.md`.

## 1. Premier lancement

MoveApps est une app de barre de menu (son icône ⇄ apparaît à droite dans la barre du haut ; elle n'apparaît pas dans le Dock par défaut). Il n'y a pas d'assistant de configuration forcé au premier lancement : l'app démarre déjà avec deux racines par défaut :

- **Actif** : `~/DevApps`
- **Archive** : `~/Documents/GitHub`

Si vos dossiers de projets sont ailleurs, ouvrez les réglages (bouton **Réglages** dans la barre d'outils de la fenêtre principale, ou dans le menu de la barre de menu, ou `⌘,`), puis cliquez sur **Choisir…** en face de chaque racine pour sélectionner le bon dossier via le sélecteur natif macOS. Un dossier de modèles optionnel (par défaut `~/DevApps/.templates`) peut aussi y être configuré, utilisé par « Nouveau projet ».

Si l'accès à un dossier est perdu (permission révoquée), la ligne correspondante affiche **« Accès perdu — à reconfigurer »** dans les réglages : recliquez sur **Choisir…** pour le sélectionner à nouveau.

**Autorisation macOS pour l'Archive.** La première fois que MoveApps lit `~/Documents/GitHub`, macOS peut afficher une demande d'autorisation d'accès au dossier Documents — acceptez-la. Si elle a été refusée par erreur, la colonne Archive affiche un message **« Accès refusé »** avec la marche à suivre : Réglages Système › Confidentialité et sécurité › Fichiers et dossiers, puis rafraîchir. `~/DevApps` n'est pas concerné par cette autorisation (ce n'est pas un dossier protégé par macOS).

## 2. Faire un premier transfert

Au lancement, MoveApps reste en barre de menu sans ouvrir sa fenêtre principale automatiquement — cliquez sur l'icône ⇄ dans la barre de menu puis sur **Ouvrir MoveApps**, ou sur l'icône dans le Dock si vous l'y avez activée. Une fois ouverte au moins une fois, la fenêtre affiche deux colonnes : **Archive** à gauche, **Actif** à droite, chacune listant ses projets (avec sous-dossiers de catégorie repliables).

Trois façons de transférer un projet d'une racine vers l'autre :

- **Glisser-déposer** : faites glisser la carte d'un projet d'une colonne vers l'autre.
- **Bouton flèche** : chaque ligne a un bouton flèche circulaire à droite qui prépare un transfert vers l'autre racine.
- **Sélection multiple** : cochez plusieurs projets (ou tout un dossier de catégorie via sa case à cocher d'en-tête, qui sélectionne tout le dossier en un clic) — une pastille flottante **« Transférer vers … »** apparaît en bas de la fenêtre pour lancer le lot en une fois.

Dans les trois cas, une **fenêtre de confirmation** s'ouvre avant que quoi que ce soit ne bouge réellement : elle permet de choisir le dossier de destination (racine, dossier de catégorie existant, ou nouveau dossier) et deux options (conserver un lien symbolique de compatibilité à l'ancien emplacement, réinstaller `node_modules`). Rien ne se transfère avant d'avoir cliqué sur **Confirmer**.

**Cas particulier — le dossier `Templates`** : ce dossier de premier niveau est une ressource partagée (scripts et squelettes référencés par les deux racines), pas un projet. Il apparaît comme une entrée unique et un transfert le **copie** au lieu de le déplacer : l'original reste en place, aucun verrou de prise n'est posé, et la fenêtre de confirmation dit « Confirmer la copie ». Pour rafraîchir une copie déjà présente de l'autre côté, supprimez-la d'abord (le transfert refuse d'écraser une destination existante).

Une fois confirmé, une pastille de progression apparaît en bas de la fenêtre pendant le transfert (indispensable pour les projets volumineux, l'opération n'est pas instantanée). À la fin, une bannière signale un problème éventuel (avertissement ou échec) ; en cas de résultat critique, la source du projet est toujours préservée par sécurité — voir l'historique pour le détail.

## 3. Le verrou de prise multi-Mac

L'Archive (`~/Documents/GitHub`) est partagée entre les Macs de Vincent via iCloud Drive. Quand un projet est pris (transféré Archive → Actif) sur un Mac, une trace reste à son ancien emplacement dans l'Archive, indiquant quel Mac l'a pris et à quelle date.

Sur les autres Macs, ce projet apparaît **verrouillé** dans la colonne Archive : une icône de cadenas et la mention « Pris par *nom-du-Mac* le *date* » remplacent les tags habituels, la case de sélection est désactivée, et le bouton flèche est remplacé par un bouton **Libérer**.

- Le moyen normal de « rendre » un projet est de le retransférer Actif → Archive : la trace est alors effacée automatiquement.
- Le bouton **Libérer** permet d'effacer manuellement une trace périmée ou erronée (par exemple si le transfert retour a échoué). Il ouvre une confirmation qui rappelle explicitement : **cela supprime uniquement la trace de prise, pas le contenu réel**, qui reste sur l'autre Mac. À n'utiliser que si vous êtes certain que personne d'autre ne travaille encore sur ce projet.

## 4. Suivre un transfert dans la fenêtre Debug

Pour un transfert qui prend du temps, la pastille de progression compacte ne montre que l'étape en cours. Le bouton **Debug** (icône coccinelle) dans la barre d'outils de la fenêtre principale ouvre une fenêtre séparée qui trace en direct, étape par étape, tout ce qui se passe pendant les transferts (détection du stack, matérialisation iCloud, déplacement, réinstallation, vérifications, avertissements…). Cette fenêtre ne s'ouvre jamais automatiquement — c'est un outil à la demande — et un bouton **Effacer** permet de vider le journal affiché.

## 5. Retrouver l'historique des transferts

Le bouton **Historique** dans la barre d'outils de la fenêtre principale ouvre la liste de tous les transferts effectués, du plus récent au plus ancien, avec pour chacun : le projet, la direction, la date, un statut coloré (OK / avertissement / critique / échec) et le détail des avertissements éventuels.
