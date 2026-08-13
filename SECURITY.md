# Sécurité

## Gestion des secrets

- **Ne jamais committer** le fichier `.env` ni aucune clé API / token.
  Le `.gitignore` exclut `.env`, `*.key`, `*.pem`, `*.crt`.
- La clé API Cortex XSIAM est **sensible** : elle est stockée uniquement dans le
  fichier `.env` du serveur (`/opt/cortex-mcp/.env`), hors du dépôt.
- En cas de doute sur une fuite de clé : **révoquer et régénérer la clé** dans la
  console XSIAM (Settings → Configurations → Integrations → API Keys).
- Utiliser une clé en **moindre privilège** (rôle en lecture si possible) et activer
  une **date d'expiration** si votre tenant le permet.

## Exposition réseau

- Le serveur MCP écoute sur `0.0.0.0:8080`. **Restreindre l'accès** aux seules IP
  des clients MCP autorisés :

  ```bash
  sudo ufw allow from <IP_CLIENT_1> to any port 8080 proto tcp
  sudo ufw enable
  ```

- Privilégier le déploiement dans un réseau privé / un segment SOC isolé.

## Recommandations Palo Alto

- Le serveur MCP peut exposer des outils **en lecture et en écriture** selon les
  outils custom déployés. Vérifier les permissions de la clé API avant d'ajouter
  des outils d'écriture.
- Toujours **revoir et valider** les actions suggérées par l'IA avant exécution.
- Le serveur officiel est fourni sous licence Palo Alto Networks — voir `NOTICE.md`.

## Signalement d'une vulnérabilité

Pour toute vulnérabilité concernant ce dépôt d'intégration, ouvrez une **issue**
sur GitHub ou contactez l'équipe sécurité interne. Ne publiez pas de détails
exploitables publiquement avant résolution.

Pour une vulnérabilité du serveur MCP officiel : contactez directement
**Palo Alto Networks** (PSIRT / support).
