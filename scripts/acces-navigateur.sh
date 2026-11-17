#!/usr/bin/env bash
# Rend staging / prod accessibles depuis le navigateur Windows (WSL2) :
# l'IP du nœud minikube (192.168.49.2) n'est joignable que depuis WSL.
#   ./scripts/acces-navigateur.sh        -> staging http://localhost:9081, prod http://localhost:9082
set -euo pipefail
pkill -f "kubectl -n legeni-(staging|prod) port-forward" 2>/dev/null || true
nohup kubectl -n legeni-staging port-forward svc/webapp 9081:80 >/dev/null 2>&1 &
nohup kubectl -n legeni-prod    port-forward svc/webapp 9082:80 >/dev/null 2>&1 &
sleep 2
echo "Staging    : http://localhost:9081"
echo "Production : http://localhost:9082"
echo "Mailpit    : http://localhost:8025   Jenkins : http://localhost:8080"
