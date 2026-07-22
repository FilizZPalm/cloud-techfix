#!/usr/bin/env bash
# infra/setup-mariadb-primary.sh
#
# Configura MariaDB 10.4 Primary su Ubuntu 24.04 (Azure VM).
# Requirements: 5.1
#
# Uso:
#   export DB_PASSWORD="<password-techfix>"
#   export REPL_PASSWORD="<password-repl>"
#   sudo -E bash infra/setup-mariadb-primary.sh
#
# Il flag -E preserva le variabili d'ambiente dell'utente in sudo.
# Lo script è idempotente: può essere eseguito più volte senza effetti collaterali.

set -euo pipefail

# ---------------------------------------------------------------------------
# Funzioni di utilità
# ---------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
warn() { echo "[WARN]  $*"; }

require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        err "Variabile d'ambiente '${var}' non impostata o vuota. Uscita."
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

require_env DB_PASSWORD
require_env REPL_PASSWORD

if [[ "$(id -u)" -ne 0 ]]; then
    err "Lo script deve essere eseguito come root (usa: sudo -E bash $0)"
fi

log "=== Setup MariaDB Primary iniziato ==="

# ---------------------------------------------------------------------------
# 1. Installazione mariadb-server
# ---------------------------------------------------------------------------

if dpkg -s mariadb-server &>/dev/null; then
    log "mariadb-server già installato — skip apt install"
else
    log "Installazione mariadb-server..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq mariadb-server || err "Installazione mariadb-server fallita"
    log "mariadb-server installato"
fi

# Assicura che mariadb sia avviato prima di scrivere la configurazione
systemctl enable mariadb --quiet
systemctl start mariadb || err "Impossibile avviare mariadb"

# ---------------------------------------------------------------------------
# 2. Scrittura configurazione Primary
# ---------------------------------------------------------------------------

CNF_FILE="/etc/mysql/mariadb.conf.d/99-primary.cnf"
log "Scrittura ${CNF_FILE}..."

cat > "${CNF_FILE}" <<'EOF'
# MariaDB Primary configuration — generato da setup-mariadb-primary.sh
[mysqld]
server-id       = 1
log_bin         = mysql-bin
binlog_format   = ROW
bind-address    = 0.0.0.0
EOF

log "Configurazione scritta in ${CNF_FILE}"

# ---------------------------------------------------------------------------
# 3. Restart mariadb e verifica binlog
# ---------------------------------------------------------------------------

log "Restart mariadb per applicare la configurazione..."
systemctl restart mariadb || err "Restart mariadb fallito"

# Verifica che SHOW MASTER STATUS restituisca un file binlog
log "Verifica SHOW MASTER STATUS..."
MASTER_STATUS=$(mysql --defaults-extra-file=<(printf '[client]\nuser=root\n') \
    -e "SHOW MASTER STATUS\G" 2>/dev/null) \
    || err "Impossibile eseguire SHOW MASTER STATUS"

if echo "${MASTER_STATUS}" | grep -q "File:.*mysql-bin\."; then
    BINLOG_FILE=$(echo "${MASTER_STATUS}" | grep "File:" | awk '{print $2}')
    BINLOG_POS=$(echo "${MASTER_STATUS}" | grep "Position:" | awk '{print $2}')
    log "Binlog attivo: file=${BINLOG_FILE}, position=${BINLOG_POS}"
else
    err "SHOW MASTER STATUS non mostra file binlog — verifica la configurazione"
fi

# ---------------------------------------------------------------------------
# 4. Creazione database grp_61_db
# ---------------------------------------------------------------------------

log "Creazione database grp_61_db (se non esiste)..."
mysql -u root <<'SQL'
CREATE DATABASE IF NOT EXISTS `grp_61_db`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
SQL
log "Database grp_61_db presente"

# ---------------------------------------------------------------------------
# 5. Creazione utente applicativo techfix@%
# ---------------------------------------------------------------------------

log "Creazione/aggiornamento utente applicativo 'techfix'@'%'..."
mysql -u root <<SQL
-- Crea utente se non esiste (idempotente con MariaDB 10.4+)
CREATE USER IF NOT EXISTS 'techfix'@'%' IDENTIFIED BY '${DB_PASSWORD}';
-- Aggiorna password in caso di seconda esecuzione
ALTER USER 'techfix'@'%' IDENTIFIED BY '${DB_PASSWORD}';
-- Privilegi sul solo database applicativo
GRANT ALL PRIVILEGES ON \`grp_61_db\`.* TO 'techfix'@'%';
FLUSH PRIVILEGES;
SQL
log "Utente 'techfix'@'%' configurato con privilegi su grp_61_db"

# ---------------------------------------------------------------------------
# 6. Creazione utente replication repl@127.0.0.1
# ---------------------------------------------------------------------------

log "Creazione/aggiornamento utente replication 'repl'@'127.0.0.1'..."
mysql -u root <<SQL
CREATE USER IF NOT EXISTS 'repl'@'127.0.0.1' IDENTIFIED BY '${REPL_PASSWORD}';
ALTER USER 'repl'@'127.0.0.1' IDENTIFIED BY '${REPL_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
log "Utente 'repl'@'127.0.0.1' configurato con privilegio REPLICATION SLAVE"

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------

log ""
log "=== Setup MariaDB Primary completato con successo ==="
log "  Binlog file    : ${BINLOG_FILE}"
log "  Binlog position: ${BINLOG_POS}"
log "  Database       : grp_61_db (utf8mb4_unicode_ci)"
log "  Utente app     : techfix@% (GRANT ALL ON grp_61_db.*)"
log "  Utente repl    : repl@127.0.0.1 (GRANT REPLICATION SLAVE)"
log ""
log "Prossimo passo: importare il dump con infra/setup-mariadb-primary.sh"
log "  mysql -u root grp_61_db < grp_61_db.sql"
