# Serveur MCP Cortex XSIAM — Intégration

Intégration d'un serveur **Model Context Protocol (MCP)** pour **Cortex XSIAM** (Palo Alto Networks), permettant à OpenCode, Claude Desktop et LM Studio d'interroger l'API Cortex XSIAM via le **serveur MCP officiel Palo Alto**.

> ⚠️ Ce dépôt contient **uniquement** la configuration et la documentation d'intégration. Le code du serveur MCP officiel est propriétaire Palo Alto et se télécharge depuis la console XSIAM (voir [NOTICE.md](NOTICE.md)).

---

## Architecture

```
OpenCode / LM Studio / Claude Desktop
        ↓  HTTP (Streamable HTTP)
Serveur Ubuntu (srv-test)
        ↓
Docker Container (cortex-mcp — serveur MCP officiel)
        ↓  API PAPI
Cortex XSIAM API
```

---

## Prérequis

- Serveur Ubuntu avec Docker installé
- Clé API Cortex XSIAM (Standard) + API Key ID
  - Console XSIAM → **Settings → Configurations → Integrations → API Keys**
- Le package **Cortex MCP Server** téléchargé depuis :
  Console XSIAM → **Settings → Configurations → Integrations → Cortex MCP Server**

### Spécifications serveur recommandées

Le serveur MCP est un proxy HTTP asynchrone (FastMCP + httpx) : la charge est
faible — le travail lourd (requêtes XQL, agrégations, corrélation) est exécuté
**côté Cortex XSIAM**, pas sur votre machine.

| Ressource | Minimal (test/POC) | Recommandé (production) |
|-----------|--------------------|--------------------------|
| CPU       | 1 vCPU             | 2 vCPU                   |
| RAM       | 1 Go               | 2 Go                     |
| Disque    | 10 Go              | 20 Go                    |
| Réseau    | LAN                | LAN à faible latence vers le tenant |

Notes :
- Le pic de RAM survient au démarrage (chargement des specs OpenAPI + outils) et
  lors de réponses XQL volumineuses (jusqu'à 1M de lignes en stream).
- Plusieurs clients MCP en parallèle (OpenCode + LM Studio + Claude Desktop) :
  privilégier **2 vCPU / 2-4 Go RAM**.
- `LLM_CONTEXT_SIZE` (32768) concerne le **client** (LM Studio/OpenCode), pas le serveur.
- La limite de l'API tenant (~10 req/s) peut provoquer des erreurs `429` : cela vient
  de XSIAM, pas du serveur. Agissez sur le volume de requêtes côté clients.

---

## Déploiement

### Déploiement automatique (Docker ou Podman) — recommandé

Un script d'installation gère l'ensemble (détection Docker/Podman, copie du package, création du `.env`, build, démarrage, test de santé) :

```bash
# 1. Télécharger le package Cortex MCP Server depuis la console XSIAM et l'extraire
# 2. Exécuter le script d'installation
sudo ./install.sh /chemin/vers/package-cortex-mcp install
```

Commandes disponibles :

| Commande | Action |
|----------|--------|
| `install <pkg>` | Installation complète (copie package, .env, build, démarrage, test) |
| `start` / `stop` | Démarrer / arrêter le conteneur |
| `status` | État du conteneur |
| `logs` | Suivre les logs en direct |
| `test` | Handshake MCP + liste des outils disponibles |
| `update` | Mettre à jour les composants Cortex (`src/cli.py update`) |
| `uninstall` | Supprimer conteneurs, image, package et `.env` du serveur |

Le script utilise **Docker** s'il est disponible, sinon **Podman**. Le `.env` est créé depuis `.env.example` et sa validation bloque le démarrage si des placeholders subsistent.

> 💡 **Matériel** : le script tourne sur des specs minimales (1 vCPU / 1 Go RAM).
> Voir le tableau [Spécifications serveur recommandées](#spécifications-serveur-recommandées) ci-dessus.

### Désinstallation via le script

La commande `uninstall` supprime **tout** du serveur : conteneurs `cortex-mcp` et
`cortex-mcp-server` (ancien placeholder), image, package et `.env`.

```bash
sudo ./install.sh uninstall
```

Vérification :

```bash
sudo docker ps -a | grep cortex || echo "Aucun conteneur cortex ✓"
sudo ls /opt/cortex-mcp 2>&1 || echo "Package supprimé ✓"
```

> ⚠️ L'opération est **irréversible** : le `.env` (clé API) et le package sont
> définitivement supprimés. Pour un simple arrêt temporaire, utilisez `stop`
> (le conteneur et ses données restent en place).

### Installation manuelle

#### 1. Préparer le dossier

Sur le serveur (`/opt/cortex-mcp` par exemple) :

```bash
sudo mkdir -p /opt/cortex-mcp
# Copier ici le contenu du package Cortex MCP Server (Dockerfile, src/, pyproject.toml...)
```

### 2. Configurer les variables d'environnement

```bash
cp deploy/.env.example .env
nano .env
```

Renseigner :
- `CORTEX_MCP_PAPI_URL` : URL API de votre tenant
- `CORTEX_MCP_PAPI_AUTH_HEADER` : clé API
- `CORTEX_MCP_PAPI_AUTH_ID` : ID de la clé API
- `MCP_TRANSPORT=streamable-http` pour l'accès HTTP

> ⚠️ Le fichier `.env` contient des secrets — **ne jamais le committer**. Il est exclu par le `.gitignore`.

### 3. Builder et démarrer

```bash
docker compose -f deploy/docker-compose.yml up -d --build
docker logs -f cortex-mcp
```

Attendu dans les logs :
```
Starting MCP server 'Cortex MCP Server' with transport 'streamable-http' on http://0.0.0.0:8080/api/v1/stream/mcp
```

### 4. Valider le serveur

```bash
curl -s -X POST http://localhost:8080/api/v1/stream/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
```

---

## Configuration des clients

### OpenCode

Voir [config/opencode.jsonc](config/opencode.jsonc) — à placer dans `~/.config/opencode/opencode.jsonc` :

```jsonc
{
  "mcp": {
    "cortex": {
      "type": "remote",
      "url": "http://<IP_SERVEUR>:8080/api/v1/stream/mcp",
      "enabled": true
    }
  }
}
```

### LM Studio

Voir [config/mcp.lmstudio.json](config/mcp.lmstudio.json) — à placer dans `.lmstudio/mcp.json` :

```json
{
  "mcpServers": {
    "cortex": {
      "url": "http://<IP_SERVEUR>:8080/api/v1/stream/mcp"
    }
  }
}
```

### Claude Desktop (Docker)

```json
{
  "mcpServers": {
    "Cortex MCP Server": {
      "command": "docker",
      "args": ["run", "--env-file", "/path/to/.env", "-i", "--rm", "cortex-mcp"]
    }
  }
}
```

### Désinstaller le MCP des LLM

Pour retirer le serveur Cortex des clients LLM (sans toucher au serveur distant) :

**OpenCode** — éditer `~/.config/opencode/opencode.jsonc` et supprimer le bloc `"cortex"` sous `"mcp"` :

```jsonc
{
  "mcp": {
    "notion": { ... }   // les autres serveurs restent
    // "cortex": { ... }  ← à supprimer
  }
}
```

**LM Studio** — éditer `.lmstudio/mcp.json` et supprimer le bloc `"cortex"` sous `"mcpServers"`, puis recharger la fenêtre MCP.

**Claude Desktop** — éditer `claude_desktop_config.json` et supprimer le bloc `"Cortex MCP Server"`.

Une fois le serveur distant coupé, les clients perdent simplement l'outillage Cortex ; il n'y a aucun fichier résiduel à nettoyer côté LLM.

---

## Outils disponibles

Le serveur expose 12 outils par défaut (via composants built-in + OpenAPI) :

| Outil | Description |
|-------|-------------|
| `get_cases` | Récupérer des cases/incidents avec filtres |
| `get_issues` | Récupérer des issues/alertes avec filtres |
| `get_assets` / `get_asset_by_id` | Inventaire des assets |
| `get_vulnerabilities` | Vulnérabilités (requiert add-on Cloud Posture) |
| `get_filtered_endpoints` | Endpoints gérés par les agents XDR |
| `get_correlation_rules` | Règles de corrélation |
| `get_audit_management_log` | Logs d'audit |
| `get_playbook` / `get_script` | Playbooks et scripts |
| `get_tenant_info` | Informations tenant |
| `get_assessment_profile_results` | Résultats d'évaluation de conformité |

Les composants supplémentaires se téléchargent via la commande `update` du serveur :
```bash
docker run --rm -it cortex-mcp python src/cli.py update
```

---

## Exemple d'appel

Cas n°148 (opérateur `in` avec valeur entière) :

```
get_cases → filters: [{"field": "case_id", "operator": "in", "value": [148]}]
```

---

## Dépannage

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `401 Unauthorized` | Clé API erronée/inactive | Vérifier `.env` |
| `Connection Refused` | URL tenant incorrecte | Vérifier `CORTEX_MCP_PAPI_URL` |
| Timeout client | URL sans `http://` ou mauvais path | Utiliser `http://<host>:8080/api/v1/stream/mcp` |
| `Value must be integer` | LLM envoie des floats | Coercer floats → int (voir README du package) |

---

## Sécurité

- **Ne jamais committer** `.env`, clés API ou tokens
- Restreindre l'accès au port 8080 (`ufw`) aux IP des clients MCP
- Clé API en **moindre privilège** (lecture si possible)
- Serveur à déployer dans un environnement sécurisé (recommandation Palo Alto)

## Licence

Ce dépôt d'intégration : voir [LICENSE](LICENSE).
Le serveur MCP officiel reste soumis à la licence Palo Alto Networks (voir [NOTICE.md](NOTICE.md)).
