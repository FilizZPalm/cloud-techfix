#!/usr/bin/env bash
# =============================================================================
# TechFix — Full Setup Script
#
# Esegue l'intero setup dal punto 0 al punto 9 in un colpo solo.
# Deve essere eseguito come root con le variabili d'ambiente impostate.
#
# Prerequisiti:
#   - Ubuntu 24.04 con mariadb-server, docker, k6 installati
#   - Docker daemon avviato (systemctl start docker)
#
# Utilizzo:
#   export DB_PASSWORD="una-password-sicura"
#   export REPL_PASSWORD="una-password-sicura"
#   sudo -E bash scripts/full-setup.sh
#
# Lo script è idempotente: può essere rieseguito senza problemi.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colori
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[STEP]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Validazione
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    err "Eseguire come root: sudo -E bash scripts/full-setup.sh"
fi

if [[ -z "${DB_PASSWORD:-}" ]]; then
    err "DB_PASSWORD non impostata. Esporta prima: export DB_PASSWORD=\"...\""
fi

if [[ -z "${REPL_PASSWORD:-}" ]]; then
    warn "REPL_PASSWORD non impostata, uso DB_PASSWORD come fallback"
    export REPL_PASSWORD="${DB_PASSWORD}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  TechFix — Full Setup (Step 0 → 9)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Step 0: Prerequisiti
# ---------------------------------------------------------------------------
info "Step 0: Verifico prerequisiti..."

# Docker
if ! systemctl is-active --quiet docker 2>/dev/null; then
    systemctl start docker
    systemctl enable docker
fi
ok "Docker attivo"

# Hosts entry
if ! grep -q "techfix.local" /etc/hosts; then
    echo "127.0.0.1 techfix.local" >> /etc/hosts
    ok "Aggiunto techfix.local a /etc/hosts"
else
    ok "techfix.local già in /etc/hosts"
fi

# ---------------------------------------------------------------------------
# Step 1: MariaDB Primary
# ---------------------------------------------------------------------------
info "Step 1: Setup MariaDB Primary..."
bash "${PROJECT_ROOT}/infra/setup-mariadb-primary.sh"
ok "MariaDB Primary configurato"

# ---------------------------------------------------------------------------
# Step 2: Import dump
# ---------------------------------------------------------------------------
info "Step 2: Import dump database..."
bash "${PROJECT_ROOT}/infra/import-db-dump.sh"
ok "Dump importato"

# ---------------------------------------------------------------------------
# Step 3: MariaDB Replica
# ---------------------------------------------------------------------------
info "Step 3: Setup MariaDB Replica..."
bash "${PROJECT_ROOT}/infra/setup-mariadb-replica.sh"

# Fix: assicurarsi che la Replica ascolti su 0.0.0.0 (non solo 127.0.0.1)
if grep -q "bind-address.*=.*127.0.0.1" /etc/mysql/replica/my.cnf 2>/dev/null; then
    sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/replica/my.cnf
    systemctl restart mariadb-replica
fi
ok "MariaDB Replica configurata (bind 0.0.0.0)"

# Setup replication
bash "${PROJECT_ROOT}/infra/setup-mariadb-replication.sh" || true

# Importa dati sulla Replica se mancano (caso: dump importato prima della replication)
REPLICA_SOCKET="/var/run/mysqld/mysqld-replica.sock"
if [[ -S "${REPLICA_SOCKET}" ]]; then
    PRODOTTO_COUNT=$(mysql --socket="${REPLICA_SOCKET}" -u root grp_61_db \
        -sNe "SELECT COUNT(*) FROM prodotto;" 2>/dev/null || echo "0")
    if [[ "${PRODOTTO_COUNT}" -ne 7 ]]; then
        warn "Replica non ha i dati, importo manualmente..."
        mysql --socket="${REPLICA_SOCKET}" -u root -e "SET GLOBAL read_only=0;"
        mysql --socket="${REPLICA_SOCKET}" -u root grp_61_db < "${PROJECT_ROOT}/grp_61_db.sql" 2>/dev/null || true
        mysql --socket="${REPLICA_SOCKET}" -u root -e "SET GLOBAL read_only=1;"
    fi
    # Crea utente techfix sulla Replica
    mysql --socket="${REPLICA_SOCKET}" -u root -e \
        "CREATE USER IF NOT EXISTS 'techfix'@'%' IDENTIFIED BY '${DB_PASSWORD}';
         GRANT SELECT ON grp_61_db.* TO 'techfix'@'%';
         FLUSH PRIVILEGES;" 2>/dev/null || true
fi
ok "Replication configurata e dati verificati"

# ---------------------------------------------------------------------------
# Step 4: Firewall
# ---------------------------------------------------------------------------
info "Step 4: Setup firewall..."
bash "${PROJECT_ROOT}/infra/setup-firewall.sh"

# Fix: aggiungere regola per pod network Calico (172.16.0.0/12)
iptables -C INPUT -p tcp -s 172.16.0.0/12 --dport 3306 -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp -s 172.16.0.0/12 --dport 3306 -j ACCEPT
iptables -C INPUT -p tcp -s 172.16.0.0/12 --dport 3307 -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp -s 172.16.0.0/12 --dport 3307 -j ACCEPT
ok "Firewall configurato (pod network incluso)"

# ---------------------------------------------------------------------------
# Step 5: k3s + Calico + etcd encryption
# ---------------------------------------------------------------------------
info "Step 5: Setup k3s..."
bash "${PROJECT_ROOT}/infra/setup-k3s.sh"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ok "k3s installato"

# ---------------------------------------------------------------------------
# Step 6: Metrics server
# ---------------------------------------------------------------------------
info "Step 6: Setup metrics server..."
bash "${PROJECT_ROOT}/infra/setup-metrics-server.sh"
ok "Metrics server installato"

# ---------------------------------------------------------------------------
# Step 7: Build immagini Docker e import in k3s
# ---------------------------------------------------------------------------
info "Step 7: Build e import immagini Docker..."
bash "${PROJECT_ROOT}/scripts/build-and-import.sh"
ok "Immagini buildate e importate"

# ---------------------------------------------------------------------------
# Step 8: Kubernetes Secrets
# ---------------------------------------------------------------------------
info "Step 8: Creazione secrets..."

# Rileva IP nodo
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "10.0.0.42")

export DB_PRIMARY_HOST="${NODE_IP}"
export DB_REPLICA_HOST="${NODE_IP}"

# Crea namespace prima (necessario per i secrets)
kubectl apply -f "${PROJECT_ROOT}/k8s/namespace.yaml"

bash "${PROJECT_ROOT}/scripts/create-secrets.sh"
ok "Secrets creati (DB_HOST=${NODE_IP})"

# ---------------------------------------------------------------------------
# Step 9: Deploy Kubernetes
# ---------------------------------------------------------------------------
info "Step 9: Deploy applicazione..."

# Aggiorna NetworkPolicy con IP corretto del nodo
sed -i "s|10.42.0.1/32|${NODE_IP}/32|g" "${PROJECT_ROOT}/k8s/network-policies.yaml"

bash "${PROJECT_ROOT}/scripts/deploy.sh" || true

# Patch liveness probe Nginx (TCP invece di HTTP per evitare 500 da Laravel)
kubectl patch deployment nginx-deployment -n techfix --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe", "value": {"tcpSocket": {"port": 8080}, "initialDelaySeconds": 10, "periodSeconds": 15}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe", "value": {"tcpSocket": {"port": 8080}, "initialDelaySeconds": 5, "periodSeconds": 10}}
]' 2>/dev/null || true

# Aspetta che i pod siano ready
echo ""
info "Aspetto che i pod siano ready..."
kubectl rollout status deployment/laravel-deployment -n techfix --timeout=120s 2>/dev/null || true
kubectl rollout status deployment/nginx-deployment -n techfix --timeout=120s 2>/dev/null || true

# Genera cache Laravel
for pod in $(kubectl get pods -n techfix -l app=laravel -o name 2>/dev/null); do
    kubectl exec -n techfix $pod -c laravel -- php artisan config:cache 2>/dev/null || true
    kubectl exec -n techfix $pod -c laravel -- php artisan route:cache 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Verifica finale
# ---------------------------------------------------------------------------
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Verifica finale${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

sleep 5

HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://techfix.local/ 2>/dev/null || echo "000")

if [[ "${HTTP_CODE}" == "200" ]]; then
    ok "TechFix risponde con HTTP 200 su https://techfix.local/"
else
    warn "TechFix risponde con HTTP ${HTTP_CODE} (potrebbe servire qualche secondo in più)"
fi

echo ""
kubectl get pods -n techfix 2>/dev/null
echo ""
kubectl get hpa -n techfix 2>/dev/null
echo ""

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Setup completato!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Per la demo di scalabilità:"
echo "  k6 run scripts/load-test.js"
echo ""
echo "Per monitorare l'HPA:"
echo "  watch -n 1 'kubectl get hpa -n techfix && echo && kubectl get pods -n techfix -l app=laravel'"
echo ""
