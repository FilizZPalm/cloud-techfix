#!/usr/bin/env bash
# infra/import-db-dump.sh
#
# Imports the grp_61_db.sql dump into the MariaDB Primary (grp_61_db database).
# Requirements: 5.1, 11.1
#
# Usage:
#   export DB_PASSWORD="<techfix-user-password>"
#   sudo -E bash infra/import-db-dump.sh
#
# The -E flag preserves the user's environment variables under sudo.
# This script is idempotent: if the `prodotto` table already contains rows,
# the import is skipped to avoid duplicate-key errors.

set -euo pipefail

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*"; }

require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        err "Environment variable '${var}' is not set or empty. Aborting."
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

require_env DB_PASSWORD

if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root (use: sudo -E bash $0)"
fi

# ---------------------------------------------------------------------------
# Resolve dump file path relative to the script directory
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUMP_FILE="${SCRIPT_DIR}/../grp_61_db.sql"

if [[ ! -f "${DUMP_FILE}" ]]; then
    err "Dump file not found at '${DUMP_FILE}'. Aborting."
fi

DUMP_FILE="$(realpath "${DUMP_FILE}")"
log "Dump file resolved to: ${DUMP_FILE}"

# ---------------------------------------------------------------------------
# Idempotency check — skip import if data already exists
# ---------------------------------------------------------------------------

log "=== Import grp_61_db dump started ==="

log "Checking whether table 'prodotto' already contains data..."
PRODOTTO_COUNT=$(mysql -u root grp_61_db \
    -sNe "SELECT COUNT(*) FROM prodotto;" 2>/dev/null || echo "0")

if [[ "${PRODOTTO_COUNT}" -gt 0 ]]; then
    warn "Table 'prodotto' already contains ${PRODOTTO_COUNT} row(s) — skipping import."
    warn "To force re-import, truncate the tables first or drop and recreate the database."
else
    # ---------------------------------------------------------------------------
    # Import dump as root
    # ---------------------------------------------------------------------------

    log "Importing dump into database 'grp_61_db'..."
    mysql -u root grp_61_db < "${DUMP_FILE}" \
        || err "mysql import failed. Check the dump file and MariaDB status."
    log "Dump imported successfully."
fi

# ---------------------------------------------------------------------------
# Post-import verification — row counts
# ---------------------------------------------------------------------------

log "Verifying row counts after import..."

PRODOTTO_COUNT=$(mysql -u root grp_61_db \
    -sNe "SELECT COUNT(*) FROM prodotto;" 2>/dev/null) \
    || err "Could not query table 'prodotto'."

USER_COUNT=$(mysql -u root grp_61_db \
    -sNe "SELECT COUNT(*) FROM user;" 2>/dev/null) \
    || err "Could not query table 'user'."

if [[ "${PRODOTTO_COUNT}" -ne 7 ]]; then
    err "Expected 7 rows in 'prodotto', found ${PRODOTTO_COUNT}. Verification failed."
fi
log "prodotto: ${PRODOTTO_COUNT} rows — OK"

if [[ "${USER_COUNT}" -ne 7 ]]; then
    err "Expected 7 rows in 'user', found ${USER_COUNT}. Verification failed."
fi
log "user: ${USER_COUNT} rows — OK"

# ---------------------------------------------------------------------------
# Verify techfix user access
# ---------------------------------------------------------------------------

log "Verifying 'techfix' user can connect and read from grp_61_db..."
mysql -u techfix -p"${DB_PASSWORD}" grp_61_db \
    -e "SELECT id, nome FROM prodotto LIMIT 3;" \
    || err "techfix user could not read from 'prodotto'. Check user credentials and grants."
log "techfix user access verified."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log ""
log "=== Import grp_61_db dump completed successfully ==="
log "  Dump file   : ${DUMP_FILE}"
log "  prodotto    : ${PRODOTTO_COUNT} rows"
log "  user        : ${USER_COUNT} rows"
log "  techfix user: access to grp_61_db confirmed"
log ""
log "Next step: configure MariaDB Replica with infra/setup-mariadb-replica.sh"
