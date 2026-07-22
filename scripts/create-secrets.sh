#!/usr/bin/env bash
# =============================================================================
# scripts/create-secrets.sh
# Crea i Kubernetes Secrets nel namespace "techfix":
#   - techfix-db-secret   (credenziali database)
#   - techfix-app-secret  (APP_KEY, APP_ENV, APP_DEBUG, APP_URL)
#   - techfix-tls-secret  (certificato TLS self-signed per techfix.local)
#
# Prerequisiti:
#   - kubectl configurato e puntato al cluster k3s
#   - Namespace "techfix" già esistente (creato da k8s/namespace.yaml)
#   - Variabili d'ambiente obbligatorie:
#       DB_PASSWORD       password dell'utente MariaDB "techfix"
#       DB_PRIMARY_HOST   IP o hostname del MariaDB Primary (es. 10.42.0.1)
#       DB_REPLICA_HOST   IP o hostname del MariaDB Replica (es. 10.42.0.1)
#
# Utilizzo:
#   export DB_PASSWORD="una-password-sicura"
#   export DB_PRIMARY_HOST="10.42.0.1"
#   export DB_REPLICA_HOST="10.42.0.1"
#   bash scripts/create-secrets.sh
#
# Lo script è idempotente: usa --dry-run=client -o yaml | kubectl apply -f -
# per non fallire se i secret esistono già.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colori e helper di output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

NAMESPACE="techfix"

# ---------------------------------------------------------------------------
# Validazione variabili d'ambiente obbligatorie
# ---------------------------------------------------------------------------
MISSING_VARS=0

if [[ -z "${DB_PASSWORD:-}" ]]; then
    error "DB_PASSWORD non è impostata. Esporta la password del database prima di eseguire questo script."
    MISSING_VARS=1
fi

if [[ -z "${DB_PRIMARY_HOST:-}" ]]; then
    error "DB_PRIMARY_HOST non è impostata. Es: export DB_PRIMARY_HOST=10.42.0.1"
    MISSING_VARS=1
fi

if [[ -z "${DB_REPLICA_HOST:-}" ]]; then
    error "DB_REPLICA_HOST non è impostata. Es: export DB_REPLICA_HOST=10.42.0.1"
    MISSING_VARS=1
fi

if [[ "$MISSING_VARS" -ne 0 ]]; then
    echo ""
    echo "Utilizzo:"
    echo "  export DB_PASSWORD=\"una-password-sicura\""
    echo "  export DB_PRIMARY_HOST=\"10.42.0.1\""
    echo "  export DB_REPLICA_HOST=\"10.42.0.1\""
    echo "  bash scripts/create-secrets.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verifica che kubectl sia disponibile e che il namespace esista
# ---------------------------------------------------------------------------
if ! command -v kubectl &>/dev/null; then
    error "kubectl non trovato. Installarlo e configurarlo per puntare al cluster k3s."
    exit 1
fi

if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    error "Namespace '$NAMESPACE' non esiste. Applicare prima k8s/namespace.yaml:"
    error "  kubectl apply -f k8s/namespace.yaml"
    exit 1
fi

info "Namespace '$NAMESPACE' trovato. Procedo con la creazione dei secret."

# ---------------------------------------------------------------------------
# 1. techfix-db-secret — credenziali database
# ---------------------------------------------------------------------------
info "Creazione secret 'techfix-db-secret'..."

kubectl create secret generic techfix-db-secret \
    --namespace="$NAMESPACE" \
    --from-literal=DB_PRIMARY_HOST="${DB_PRIMARY_HOST}" \
    --from-literal=DB_PRIMARY_PORT="3306" \
    --from-literal=DB_REPLICA_HOST="${DB_REPLICA_HOST}" \
    --from-literal=DB_REPLICA_PORT="3307" \
    --from-literal=DB_DATABASE="grp_61_db" \
    --from-literal=DB_USERNAME="techfix" \
    --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

info "'techfix-db-secret' applicato con successo."

# ---------------------------------------------------------------------------
# 2. techfix-app-secret — configurazione applicativa Laravel
# ---------------------------------------------------------------------------
info "Creazione secret 'techfix-app-secret'..."

kubectl create secret generic techfix-app-secret \
    --namespace="$NAMESPACE" \
    --from-literal=APP_KEY="base64:bAcPAEd6NqoIKaPrwKfpMzqvfTb3Qi4tFt65IbGyVM0=" \
    --from-literal=APP_ENV="production" \
    --from-literal=APP_DEBUG="false" \
    --from-literal=APP_URL="https://techfix.local" \
    --dry-run=client -o yaml | kubectl apply -f -

info "'techfix-app-secret' applicato con successo."

# ---------------------------------------------------------------------------
# 3. techfix-tls-secret — certificato TLS self-signed per techfix.local
# ---------------------------------------------------------------------------
info "Generazione certificato TLS self-signed per 'techfix.local'..."

# Usa una directory temporanea che viene rimossa all'uscita
TLS_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TLS_TMP_DIR"' EXIT

TLS_KEY="${TLS_TMP_DIR}/tls.key"
TLS_CERT="${TLS_TMP_DIR}/tls.crt"

openssl req -x509 -nodes \
    -newkey rsa:2048 \
    -keyout "$TLS_KEY" \
    -out "$TLS_CERT" \
    -days 365 \
    -subj "/CN=techfix.local/O=TechFix/C=IT" \
    -addext "subjectAltName=DNS:techfix.local" \
    2>/dev/null

info "Certificato generato. Creazione secret 'techfix-tls-secret'..."

kubectl create secret tls techfix-tls-secret \
    --namespace="$NAMESPACE" \
    --cert="$TLS_CERT" \
    --key="$TLS_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

info "'techfix-tls-secret' applicato con successo."

# ---------------------------------------------------------------------------
# Riepilogo finale
# ---------------------------------------------------------------------------
echo ""
info "=== Tutti i secret sono stati creati nel namespace '$NAMESPACE' ==="
echo ""
kubectl get secrets -n "$NAMESPACE" | grep -E "NAME|techfix-db-secret|techfix-app-secret|techfix-tls-secret" || true
echo ""
info "Per verificare i valori (in base64): kubectl get secret <nome> -n $NAMESPACE -o yaml"
