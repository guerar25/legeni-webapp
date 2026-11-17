# Legeni WebApp – chaîne CI/CD « du commit à la production »

Application Flask + Redis livrée automatiquement par **Jenkins → Docker Hub → Ansible → Kubernetes (Minikube)**.

| Élément | Emplacement |
|---|---|
| Application, tests | `app.py`, `tests/` |
| Image (multi-stage, non-root, healthcheck) | `Dockerfile` |
| Version sémantique | `VERSION` (tag d'image `<VERSION>-<build>`) |
| Pipeline CI/CD | `Jenkinsfile` |
| Infrastructure (Docker, Minikube, Jenkins) | `ansible/provision.yml` + `ansible/roles/` |
| Déploiement Kubernetes (rollback auto) | `ansible/deploy.yml` + `ansible/templates/k8s/app.yml.j2` |
| Paramètres / secrets | `ansible/vars/{staging,prod}.yml`, `ansible/vars/vault.yml` (Vault) |
| Rapport | `docs/rapport.md` |

## Démarrage rapide

```bash
cd ansible
echo '<mot de passe vault>' > .vault_pass && chmod 600 .vault_pass   # jamais commité
ansible-playbook provision.yml -K                                      # Docker + Minikube + Jenkins
ansible-playbook deploy.yml --vault-password-file .vault_pass \
    -e target_env=staging -e app_version=1.0.0                          # déploiement manuel
```

Staging : http://192.168.49.2:30081 (`staging.legeni.local`) – Production : http://192.168.49.2:30082 (`legeni.local`)
