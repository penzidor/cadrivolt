@echo off
cd /d "%~dp0"
echo Ouverture de APEX sur http://127.0.0.1:5173
echo Gardez cette fenetre ouverte pendant l'utilisation.
node scripts/run-framework.mjs dev --port 5173 --hostname 127.0.0.1
pause
