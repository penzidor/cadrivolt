# Cadrivolt — GitHub Pages + Supabase

Application web avec authentification Supabase, annonces, photos, favoris, demandes, messagerie et administration. Ce paquet remplace la présentation HTML précédente. Aucun compte fictif n’est utilisé par défaut.

Site publié : https://penzidor.github.io/cadrivolt/ — administration : https://penzidor.github.io/cadrivolt/admin/

## Notifications

Les migrations `004_notifications.sql` puis `005_web_push.sql` ajoutent une boîte privée persistante et les abonnements par appareil. Déployer `supabase/functions/cadrivolt-push/index.ts` comme Edge Function `cadrivolt-push`, avec la configuration `supabase/config.toml`, puis exécuter `006_push_schedule.sql` sur Supabase. La fonction vérifie elle-même le JWT du membre ou le jeton privé du planificateur. Les clés Web Push sont générées côté serveur au premier abonnement et restent dans la base privée. Ne jamais les copier dans `config.js`.

La cloche permet de consulter les 50 dernières notifications, de remonter l’historique, de marquer comme lu et d’activer ou désactiver les alertes sur l’appareil courant. Les alertes concernent les nouvelles demandes, les réponses, les messages et les changements de lieu, date, heure, prix ou statut d’une session. Les activités antérieures à l’installation ne génèrent pas rétroactivement d’alertes. La liste se rafraîchit à son ouverture et périodiquement lorsque le site est visible.

Le planificateur traite les alertes mobiles chaque minute, avec cinq tentatives au maximum et retrait des appareils expirés. Le contenu des messages privés n’apparaît pas sur l’écran verrouillé. L’utilisateur doit autoriser les notifications sur chaque appareil. Sur iPhone/iPad (iOS 16.4+), ajouter l’app à l’écran d’accueil puis l’ouvrir depuis cette icône. Les notifications push sont indépendantes du fournisseur SMTP ; les e-mails d’inscription nécessitent toujours SMTP.

**Démarrer : ouvrir INSTALLATION.html.** Il faut créer le projet Supabase, exécuter `supabase/001_cadrivolt.sql`, renseigner les deux valeurs publiques de `config.js`, puis déposer le contenu de ce dossier sur GitHub Pages. Les dossiers `admin/` et `reset/` sont de vraies pages statiques. Utiliser HTTPS après publication.

La connexion administrateur utilise votre adresse e-mail Supabase et votre mot de passe. Le rôle administrateur est accordé explicitement avec `supabase/002_admin.sql` après création et confirmation du compte. Le mot de passe de la précédente version locale n’est pas transféré automatiquement dans Supabase.

Ne jamais ajouter de clé `service_role`, `sb_secret_`, de mot de passe PostgreSQL ni de sauvegarde privée au dépôt. Les comptes et données de la version D1 locale ne sont pas exportés ni envoyés à Supabase par ce paquet.

Les confirmations d’inscription et la récupération du mot de passe nécessitent un service e-mail Supabase opérationnel ; pour les utilisateurs publics, configurer un fournisseur SMTP. Le guide explique la restriction du service e-mail par défaut. La clé publique du navigateur est prévue pour être publique ; les autorisations sont contrôlées par les fonctions SQL et les règles Storage.

## Validation

Le script SQL est testé avec PostgreSQL embarqué (PGlite), en émulant `auth.uid()` et les tables Storage. Les tests couvrent autorisations, confidentialité, inscriptions fermées, suspension, capacité, modération, export et propriété des photos. Cela ne remplace pas un essai sur le projet Supabase réel : l’authentification hébergée, les e-mails et le stockage distant nécessitent sa configuration.

Le code source maintenable se trouve dans le projet de travail `apex` : `supabase-web/`, `supabase/`, `app/`, `lib/` et `scripts/export-supabase.mjs`. Ce dossier de publication contient les fichiers déjà compilés : aucune installation n’est nécessaire pour GitHub Pages.

## Régénérer depuis le projet source

```sh
node scripts/test-supabase.mjs
node scripts/export-supabase.mjs
```

L’export préserve un `config.js` déjà renseigné dans le dossier de publication. Les données partagées sont dans Supabase ; aucune base n’est incluse dans le ZIP.

## Photos de profil
Exécuter `supabase/007_profile_photos.sql` après la migration 001. Dans Mon profil, importer ou retirer une photo puis enregistrer. JPG, PNG ou WebP, 8 Mo maximum. Les anciennes images restent dans Storage après retrait ; le profil revient aux initiales.
