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

---

## Déploiement

### 1. Préparer le dossier

Sur le serveur (`/opt/cortex-mcp` par exemple) :

```bash
sudo mkdir -p /opt/cortex-mcp
# Copier ici le contenu du package Cortex MCP Server (Dockerfile, src/, pyproject.toml...)
```

### 2. Configurer les variables d'environnement

```bash
cp .env.example .env
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
docker compose up -d --build
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
