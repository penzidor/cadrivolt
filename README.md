# APEX

Application web en français pour connecter carspotters et propriétaires et organiser des shootings, rollings, rassemblements, vidéos et road trips.

## Démarrer sur cet ordinateur

Double-cliquer sur **START-APEX.bat**, puis ouvrir <http://127.0.0.1:5173/>. Garder la fenêtre du serveur ouverte. Si le serveur tourne déjà, ouvrir directement l’adresse.

Les dépendances et la base locale sont déjà installées. Node.js 22.13 ou ultérieur est nécessaire.

Le bouton de connexion ouvre le compte de démonstration local fourni par le starter Sites. Compléter son profil, puis cliquer sur « Créer une session ». Cette connexion locale représente un seul utilisateur : elle ne constitue pas une inscription publique.

## Fonctionnalités

- Recherche de sessions par texte, type, ville et date ; filtre gratuit et tri par prix/date.
- Profils carspotter, propriétaire ou les deux, avec ville, présentation et voiture/matériel.
- Création d’annonces avec date, heure, description, nombre de places et participation indicative.
- Favoris persistants par membre.
- Demandes de participation, acceptation/refus par l’organisateur et contrôle atomique de la capacité.
- Messagerie privée entre organisateur et candidat ; actualisation automatique toutes les 15 secondes dans « Mes sessions ».
- Interface adaptative, navigation au clavier et fenêtres modales accessibles.

Les six annonces et trois profils marqués « Exemple » sont fictifs et ne peuvent pas recevoir de demandes. Trois photographies d’ambiance sont proposées ; l’import de photos personnelles et les paiements ne sont pas implémentés.

## Données et architecture

React/TypeScript, Vinext/Vite, Drizzle et Cloudflare D1. Les données locales sont persistées dans `.wrangler/state` et ne sont pas envoyées à un serveur distant. Elles sont distinctes des données d’un éventuel déploiement. Ne pas supprimer ce dossier pour conserver ses essais.

- `app/apex.tsx` : interface et interactions.
- `app/globals.css` : styles et points de rupture mobile/tablette.
- `app/api/community/route.ts` : API, validations et autorisations.
- `db/schema.ts`, `drizzle/` : schéma et migration SQL.
- `lib/demo.ts` : contenus d’exemple.
- `public/images/` : photos d’ambiance téléchargées depuis Unsplash.

Les identités en production sont fournies par la passerelle Sites. L’API autorise chaque écriture et isole demandes, messages et favoris. Ne pas exposer directement le Worker hors de cette passerelle : les en-têtes d’identité doivent provenir d’un proxy de confiance. L’aperçu et les tests écoutent uniquement sur `127.0.0.1`.

## Validation effectuée

Compilation de production et contrôle TypeScript réussis. Tests navigateur : filtre Rolling, connexion locale, sauvegarde du profil et publication d’une annonce. Les données temporaires du test navigateur ont été retirées. Les 27 tests d’intégration couvrent la persistance, l’authentification requise, l’origine des requêtes, les permissions, la capacité, les favoris et la confidentialité des conversations.

La feuille de style prévoit des dispositions à 540, 800 et 1100 pixels. Le contrôle visuel a été fait dans l’aperçu intégré ; aucun essai sur téléphone physique n’a été effectué.

La reprise du 21 octobre ajoute 12 vérifications des dates : passage de minuit en France, heure d’été/hiver, dates impossibles et années bissextiles. Le formulaire et l’API utilisent le fuseau Europe/Paris. Les fenêtres modales possèdent désormais un nom accessible relié à leur titre.

```powershell
node scripts/test-dates.mjs
```

Pour contrôler les types et compiler :

```powershell
node node_modules/typescript/bin/tsc --noEmit
node scripts/run-framework.mjs build
```

Les tests utilisent une base distincte `.wrangler/qa`. À sa première initialisation seulement :

```powershell
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/qa --file drizzle/0000_optimal_krista_starr.sql
```

Lancer le serveur de test puis, dans un autre terminal, les vérifications :

```powershell
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js dev --config dist/server/wrangler.json --local --persist-to .wrangler/qa --ip 127.0.0.1 --port 8787 --inspector-port 0
node scripts/test-api.mjs
```

Ces tests simulent la passerelle d’identité uniquement sur le serveur local et créent des comptes fictifs dans la base isolée.

## Publication

Non déployée : l’appel de création Sites a renvoyé « tool is not available to the model ». Aucun identifiant de Site n’a été obtenu. Le manifeste `.openai/hosting.json` contient la liaison D1 `DB` mais pas de `project_id`. Il faudra reprendre la procédure Sites lorsque le connecteur sera disponible, puis synchroniser la source et déployer avec les migrations. Le build validé est dans `dist/`.

Nouvelle vérification le 21 octobre : la consultation des Sites et la recherche dans les plugins renvoient également une indisponibilité des outils. Aucun changement de connexion ni de publication n’a été effectué.

## Images

Photographies d’ambiance Unsplash :

- Porsche Panamera : `https://images.unsplash.com/photo-1503376780353-7e6692767b70`
- Chevrolet Camaro : `https://images.unsplash.com/photo-1492144534655-ae79c964c9d7`
- BMW M5 : `https://images.unsplash.com/photo-1555215695-3004980ad54e`

Les polices DM Sans et Manrope sont chargées depuis Google Fonts avec repli système si elles sont indisponibles.
