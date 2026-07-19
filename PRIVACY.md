# Confidentialité

MoveApps est un outil 100% local : il lit et déplace des dossiers de projets sur votre Mac, et n'envoie aucune donnée — chemins de fichiers, contenu de projets, ou information personnelle — à un serveur tiers, ni à Vincent Lauriat, ni à qui que ce soit d'autre. L'app ne contient aucune télémétrie, aucun analytics, aucun tracker.

## La seule requête réseau automatique

MoveApps vérifie périodiquement (au lancement, puis toutes les 24h) si une nouvelle version est disponible, via [Sparkle](https://sparkle-project.org/). Concrètement, cette vérification :

- contacte GitHub pour lire `appcast.xml` sur le dépôt public [`vincentlauriat/MoveApps`](https://github.com/vincentlauriat/MoveApps) ;
- télécharge le DMG de la nouvelle version depuis GitHub Releases si une mise à jour est disponible ;
- **n'installe jamais rien automatiquement** — l'utilisateur doit toujours confirmer explicitement via le menu « Rechercher les mises à jour… ».

Aucune autre requête réseau n'est effectuée par l'app : les transferts de projets, le verrou de prise multi-Mac et l'historique restent des opérations purement locales (disque et, pour l'Archive partagée, synchronisation iCloud Drive gérée par macOS lui-même, pas par MoveApps).

## Licence

MoveApps est distribué sous licence MIT — voir [`LICENSE`](LICENSE).
