# Cadrivolt — GitHub Pages + Supabase

Application web avec authentification Supabase, annonces, photos, favoris, demandes, messagerie et administration. Ce paquet remplace la présentation HTML précédente. Aucun compte fictif n’est utilisé par défaut.

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
