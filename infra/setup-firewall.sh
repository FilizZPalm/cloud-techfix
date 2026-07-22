#!/usr/bin/env bash
# infra/setup-firewall.sh
#
# Configures iptables firewall rules to protect MariaDB ports 3306 and 3307
# on the Azure VM (Ubuntu 24.04).
#
# Allowed sources:
#   - 10.42.0.0/16  (k3s pod network CIDR — Laravel pods reach MariaDB via 10.42.0.1)
#   - 127.0.0.1     (loopback — used for internal Primary → Replica binlog replication)
#
# All other inbound connections to ports 3306 and 3307 are DROPped.
#
# Requirements: 8.5, 8.6
#
# Usage:
#   sudo bash infra/setup-firewall.sh
#
# This script is idempotent: each rule is checked with 'iptables -C' before
# being added, so re-running it does not produce duplicate rules.

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*"; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root (use: sudo bash $0)"
fi

# Verify iptables is available
if ! command -v iptables &>/dev/null; then
    err "iptables is not installed. Install it with: apt-get install -y iptables"
fi

log "=== Firewall setup for MariaDB ports 3306 / 3307 started ==="

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

K3S_POD_CIDR="10.42.0.0/16"
LOOPBACK_IP="127.0.0.1"
MYSQL_PRIMARY_PORT="3306"
MYSQL_REPLICA_PORT="3307"
IPTABLES_RULES_FILE="/etc/iptables/rules.v4"

# ---------------------------------------------------------------------------
# Helper: add a rule only if it does not already exist (idempotent)
# ---------------------------------------------------------------------------

# add_rule_if_missing <chain> <rule-spec...>
#   Checks with 'iptables -C' first; adds with 'iptables -A' only if absent.
add_rule_if_missing() {
    local chain="$1"
    shift
    local rule_spec=("$@")

    if iptables -C "${chain}" "${rule_spec[@]}" &>/dev/null 2>&1; then
        log "Rule already present — skipping: iptables -A ${chain} ${rule_spec[*]}"
    else
        iptables -A "${chain}" "${rule_spec[@]}"
        log "Rule added: iptables -A ${chain} ${rule_spec[*]}"
    fi
}

# ---------------------------------------------------------------------------
# Step 1: ACCEPT — k3s pod network CIDR → port 3306 and 3307
# ---------------------------------------------------------------------------

log "Step 1: Allowing connections from k3s pod CIDR (${K3S_POD_CIDR}) to ports ${MYSQL_PRIMARY_PORT} and ${MYSQL_REPLICA_PORT}..."

add_rule_if_missing INPUT \
    -s "${K3S_POD_CIDR}" -p tcp --dport "${MYSQL_PRIMARY_PORT}" -j ACCEPT

add_rule_if_missing INPUT \
    -s "${K3S_POD_CIDR}" -p tcp --dport "${MYSQL_REPLICA_PORT}" -j ACCEPT

# ---------------------------------------------------------------------------
# Step 2: ACCEPT — loopback (127.0.0.1) → port 3306 and 3307
#         Required for binlog replication: Primary → Replica on same VM
# ---------------------------------------------------------------------------

log "Step 2: Allowing loopback connections (${LOOPBACK_IP}) to ports ${MYSQL_PRIMARY_PORT} and ${MYSQL_REPLICA_PORT}..."

add_rule_if_missing INPUT \
    -s "${LOOPBACK_IP}/32" -p tcp --dport "${MYSQL_PRIMARY_PORT}" -j ACCEPT

add_rule_if_missing INPUT \
    -s "${LOOPBACK_IP}/32" -p tcp --dport "${MYSQL_REPLICA_PORT}" -j ACCEPT

# ---------------------------------------------------------------------------
# Step 3: DROP — all other connections to port 3306 and 3307
# ---------------------------------------------------------------------------

log "Step 3: Dropping all other connections to ports ${MYSQL_PRIMARY_PORT} and ${MYSQL_REPLICA_PORT}..."

add_rule_if_missing INPUT \
    -p tcp --dport "${MYSQL_PRIMARY_PORT}" -j DROP

add_rule_if_missing INPUT \
    -p tcp --dport "${MYSQL_REPLICA_PORT}" -j DROP

# ---------------------------------------------------------------------------
# Step 4: Persist rules
# ---------------------------------------------------------------------------

log "Step 4: Persisting iptables rules..."

# Ensure the target directory exists (iptables-persistent reads from here)
mkdir -p "$(dirname "${IPTABLES_RULES_FILE}")"

iptables-save > "${IPTABLES_RULES_FILE}" \
    || err "Failed to save iptables rules to ${IPTABLES_RULES_FILE}"

log "Rules saved to ${IPTABLES_RULES_FILE}"

# Install iptables-persistent non-interactively so rules survive reboots
if dpkg -s iptables-persistent &>/dev/null; then
    log "iptables-persistent already installed — skipping apt install"
else
    log "Installing iptables-persistent (non-interactive)..."
    export DEBIAN_FRONTEND=noninteractive
    # Pre-seed debconf so the installer does not prompt to save current rules
    # (we already saved them above)
    if command -v debconf-set-selections &>/dev/null; then
        echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" \
            | debconf-set-selections
        echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" \
            | debconf-set-selections
    fi
    apt-get update -qq
    apt-get install -y -qq iptables-persistent \
        || err "Failed to install iptables-persistent"
    log "iptables-persistent installed"
fi

# ---------------------------------------------------------------------------
# Step 5: Verification summary — show active rules on ports 3306 and 3307
# ---------------------------------------------------------------------------

log ""
log "=== Verification summary: active iptables rules for ports 3306 and 3307 ==="
log ""

# Show the full INPUT chain and filter to the two ports so the operator can
# see the exact rule order (ACCEPT entries must appear before DROP entries).
iptables -L INPUT -n --line-numbers -v \
    | grep -E "^Chain|num|dpt:(3306|3307)" \
    || warn "No rules found for ports 3306/3307 in the INPUT chain (unexpected)"

log ""

# Explicit pass/fail check for each expected rule
check_rule() {
    local label="$1"
    shift
    if iptables -C INPUT "$@" &>/dev/null 2>&1; then
        log "  [OK] ${label}"
    else
        warn "  [MISSING] ${label}"
    fi
}

check_rule "ACCEPT  ${K3S_POD_CIDR} → :${MYSQL_PRIMARY_PORT}" \
    -s "${K3S_POD_CIDR}" -p tcp --dport "${MYSQL_PRIMARY_PORT}" -j ACCEPT

check_rule "ACCEPT  ${K3S_POD_CIDR} → :${MYSQL_REPLICA_PORT}" \
    -s "${K3S_POD_CIDR}" -p tcp --dport "${MYSQL_REPLICA_PORT}" -j ACCEPT

check_rule "ACCEPT  ${LOOPBACK_IP}/32 → :${MYSQL_PRIMARY_PORT}" \
    -s "${LOOPBACK_IP}/32" -p tcp --dport "${MYSQL_PRIMARY_PORT}" -j ACCEPT

check_rule "ACCEPT  ${LOOPBACK_IP}/32 → :${MYSQL_REPLICA_PORT}" \
    -s "${LOOPBACK_IP}/32" -p tcp --dport "${MYSQL_REPLICA_PORT}" -j ACCEPT

check_rule "DROP    any → :${MYSQL_PRIMARY_PORT}" \
    -p tcp --dport "${MYSQL_PRIMARY_PORT}" -j DROP

check_rule "DROP    any → :${MYSQL_REPLICA_PORT}" \
    -p tcp --dport "${MYSQL_REPLICA_PORT}" -j DROP

log ""
log "=== Firewall setup for MariaDB completed successfully ==="
log "  Rules file    : ${IPTABLES_RULES_FILE}"
log "  Port 3306     : ACCEPT from ${K3S_POD_CIDR}, ${LOOPBACK_IP} | DROP all others"
log "  Port 3307     : ACCEPT from ${K3S_POD_CIDR}, ${LOOPBACK_IP} | DROP all others"
log ""
log "Next step: set up k3s with Calico using infra/setup-k3s.sh (task 4.1)"
