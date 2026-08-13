# À propos du serveur MCP officiel Cortex

Le code du serveur MCP (dossier `src/`, `Dockerfile`, `pyproject.toml`, etc.) **n'est pas inclus dans ce dépôt**.

Il s'agit d'un logiciel propriétaire **Palo Alto Networks**, distribué sous la licence
« *Palo Alto Networks Cortex Communication Python Files - License 1.0* » (voir le fichier
`LICENSE` inclus dans le package). Cette licence :

- autorise l'usage du logiciel **uniquement avec les produits Cortex** (XSIAM, XDR, Cloud, AgentiX) ;
- autorise la redistribution **uniquement sous la même licence** et **en incluant la licence** ;
- n'autorise pas l'usage des marques Palo Alto.

## Comment obtenir le serveur

Téléchargez le package depuis la console Cortex XSIAM :

1. **Settings → Configurations → Integrations → Cortex MCP Server**
2. Cliquez **Download MCP File**
3. (Optionnel) Vérifiez le fichier de sommes de contrôle (`checksum`) fourni
4. Extrayez le `.zip` — suivez le `README.md` du package

## Ce que contient ce dépôt

- `README.md` : guide d'intégration et de déploiement
- `deploy/` : `docker-compose.yml` et `.env.example`
- `config/` : exemples de configuration pour OpenCode et LM Studio
- `LICENSE` : licence du présent dépôt d'intégration

Aucun secret (clé API, tokens) n'est présent dans ce dépôt. Toute configuration locale
(`.env`) est exclue via le `.gitignore`.