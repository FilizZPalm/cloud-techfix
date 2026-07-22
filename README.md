# TechFix — Cloud-Native Migration

Migrazione cloud-native di TechFix, un'applicazione web Laravel 10 per la gestione dell'assistenza tecnica post-vendita. Il sistema viene containerizzato e orchestrato con Kubernetes su una singola VM Ubuntu 24.04.

## Architettura

```
┌──────────────────────────────────────────────────────────────────┐
│              VM Ubuntu 24.04 (4 vCPU, 15 GB RAM)                 │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              k3s Cluster (single-node)                   │   │
│  │                                                          │   │
│  │  Traefik Ingress (TLS :443, redirect HTTP→HTTPS)        │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  Nginx Pod ──FastCGI:9000──▶ Laravel Pod (PHP-FPM)      │   │
│  │                              Laravel Pod 2  (HPA)        │   │
│  │                              ...                         │   │
│  │                              Laravel Pod N  (max=10)     │   │
│  │                                                          │   │
│  │  Calico CNI (NetworkPolicy enforcement)                  │   │
│  │  HPA: min=2, max=10, target CPU=70%                     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                    │ writes :3306        │ reads :3307           │
│                    ▼                     ▼                       │
│       MariaDB Primary (host)    MariaDB Replica (host)          │
│       binlog replication ──────────────────▶                    │
└──────────────────────────────────────────────────────────────────┘
```

**Stack tecnologico:**

| Layer | Tecnologia |
|---|---|
| Orchestrazione | k3s (Kubernetes leggero) |
| Ingress | Traefik (integrato in k3s, TLS self-signed) |
| CNI | Calico (NetworkPolicy support) |
| App server | PHP-FPM 8.2 (container Docker multi-stage) |
| Web server | Nginx (reverse proxy, file statici) |
| Database | MariaDB 10.11+ Primary (:3306) + Replica (:3307) |
| Autoscaling | Kubernetes HPA (CPU-based) |
| Secrets | K8s Secrets + etcd encryption at rest (aescbc) |
| Load testing | k6 |

---

## Prerequisiti

Sulla VM Ubuntu 24.04 devono essere installati:

- `mariadb-server` (10.11+)
- `docker` (per il build delle immagini — **avviarlo con** `sudo systemctl start docker`)
- `k3s` (installato dallo script, richiede `curl`)
- `kubectl` (incluso con k3s: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`)
- `k6` (per il load test della demo di scalabilità)
- `openssl` (per generare certificati TLS e chiavi di encryption)
- `bc` (per il calcolo dimensioni immagini)

---

## Struttura del progetto

```
TechFix-main/
├── docker/
│   ├── laravel/Dockerfile       # Multi-stage: builder → production (PHP-FPM)
│   └── nginx/
│       ├── Dockerfile           # Nginx con file statici
│       └── nginx.conf           # Configurazione reverse proxy
├── infra/
│   ├── setup-mariadb-primary.sh # Installazione e config MariaDB Primary
│   ├── setup-mariadb-replica.sh # Setup seconda istanza (porta 3307)
│   ├── setup-mariadb-replication.sh # Configurazione binlog replication
│   ├── import-db-dump.sh        # Import del dump grp_61_db.sql
│   ├── setup-k3s.sh            # Installazione k3s + Calico + etcd encryption
│   ├── setup-metrics-server.sh  # Metrics server per HPA
│   ├── setup-firewall.sh       # iptables: accesso MySQL solo da pod network
│   ├── verify-traefik.sh       # Verifica Traefik Ingress Controller
│   └── verify-etcd-encryption.sh
├── k8s/
│   ├── namespace.yaml           # Namespace: techfix
│   ├── configmaps/nginx-config.yaml
│   ├── laravel-deployment.yaml  # 2 repliche, SecurityContext hardened
│   ├── nginx-deployment.yaml    # 1 replica, read-only filesystem
│   ├── services.yaml            # ClusterIP services
│   ├── laravel-hpa.yaml         # HPA min=2, max=10, cpu=70%
│   ├── ingress.yaml             # Traefik Ingress con TLS
│   ├── network-policies.yaml    # Isolamento traffico pod-to-pod
│   └── metrics-server.yaml
├── scripts/
│   ├── build-and-import.sh      # Build Docker + import in k3s containerd
│   ├── create-secrets.sh        # Creazione K8s Secrets (DB, APP, TLS)
│   ├── deploy.sh               # Deploy orchestrato di tutti i manifest
│   └── load-test.js            # k6 script per demo scalabilità
├── laraProject/                 # Codice sorgente Laravel 10
├── grp_61_db.sql               # Dump database MariaDB
└── README.md                   # Questo file
```

---

## Deployment step-by-step

> **Nota importante:** Tutti gli script `infra/` richiedono `sudo -E` per passare le variabili d'ambiente. Impostare **prima** di tutto:
> ```bash
> export DB_PASSWORD="una-password-sicura"
> export REPL_PASSWORD="una-password-sicura"
> export DB_PRIMARY_HOST="10.42.0.1"
> export DB_REPLICA_HOST="10.42.0.1"
> ```

### 0. Prerequisiti runtime

```bash
# Avviare Docker (se non parte al boot)
sudo systemctl start docker
sudo systemctl enable docker

# Aggiungere il proprio utente al gruppo docker (evita sudo per i build)
sudo usermod -aG docker $USER
newgrp docker
```

### 1. Setup MariaDB Primary

```bash
sudo -E bash infra/setup-mariadb-primary.sh
```

Configura `server-id=1`, abilita binlog, crea il database `grp_61_db` e gli utenti `techfix` (applicativo) e `repl` (replication).

### 2. Importare il dump del database

```bash
sudo -E bash infra/import-db-dump.sh
```

Importa `grp_61_db.sql` sul Primary. Verificare:

```bash
sudo mysql -e "SELECT COUNT(*) FROM grp_61_db.prodotto;"
# Atteso: 7
```

### 3. Setup MariaDB Replica (porta 3307)

```bash
sudo -E bash infra/setup-mariadb-replica.sh
sudo -E bash infra/setup-mariadb-replication.sh
```

Crea una seconda istanza MariaDB su porta 3307 con `read_only=1` e configura la replication binlog dal Primary.

> **Nota:** Se il dump è stato importato prima della replication, i dati non si replicano automaticamente. In quel caso, importare manualmente sulla Replica:
> ```bash
> sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "CREATE DATABASE IF NOT EXISTS grp_61_db;"
> sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SET GLOBAL read_only=0;"
> sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock grp_61_db < grp_61_db.sql
> sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SET GLOBAL read_only=1;"
> ```

Verificare:

```bash
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
# Atteso: Slave_IO_Running: Yes, Slave_SQL_Running: Yes, Seconds_Behind_Master: 0
```

### 4. Configurare il firewall

```bash
sudo bash infra/setup-firewall.sh
```

Imposta regole iptables che consentono connessioni a MariaDB (porte 3306/3307) solo dal pod network k3s (`10.42.0.0/16`) e dal loopback.

### 5. Installare k3s con Calico e etcd encryption

```bash
sudo bash infra/setup-k3s.sh
```

Installa k3s con:
- `--cluster-init` (etcd embedded per encryption at rest)
- `--flannel-backend=none` (sostituito da Calico per NetworkPolicy)
- Encryption at rest con provider `aescbc`
- Calico CNI

Dopo l'installazione, configurare kubectl:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
# Atteso: nodo in stato Ready
```

### 6. Installare Metrics Server

```bash
sudo bash infra/setup-metrics-server.sh
```

Necessario per il funzionamento dell'HPA. Verificare:

```bash
kubectl top nodes
```

### 7. Build immagini Docker e import in k3s

```bash
bash scripts/build-and-import.sh
```

Costruisce le immagini multi-stage per Laravel (PHP-FPM) e Nginx, le importa nel runtime containerd di k3s. Stampa un avviso se l'immagine Laravel supera 500 MB.

### 8. Creare i Kubernetes Secrets

```bash
export DB_PASSWORD="una-password-sicura"
export DB_PRIMARY_HOST="10.42.0.1"
export DB_REPLICA_HOST="10.42.0.1"

bash scripts/create-secrets.sh
```

Crea tre secret nel namespace `techfix`:
- `techfix-db-secret` — credenziali database (Primary e Replica)
- `techfix-app-secret` — APP_KEY, APP_ENV, APP_DEBUG, APP_URL
- `techfix-tls-secret` — certificato TLS self-signed per `techfix.local`

### 9. Deploy dell'applicazione

```bash
bash scripts/deploy.sh
```

Applica i manifest Kubernetes nell'ordine corretto:
1. Namespace
2. ConfigMaps
3. NetworkPolicies
4. Deployments (Laravel + Nginx)
5. Services
6. HPA
7. Ingress

Attende il rollout completo di entrambi i deployment e mostra lo stato finale del cluster.

### 10. Verifica

```bash
# Pod in esecuzione
kubectl get pods -n techfix

# HPA attivo
kubectl get hpa -n techfix

# Accesso HTTPS (con certificato self-signed)
curl -k https://techfix.local/

# Verifica TLS
openssl s_client -connect techfix.local:443 -servername techfix.local < /dev/null 2>/dev/null | openssl x509 -noout -subject
```

> Per accedere a `techfix.local` dalla macchina locale, aggiungere al file `/etc/hosts`:
> ```
> <IP-VM>  techfix.local
> ```

---

## Demo scalabilità (Product Recall)

La demo mostra l'HPA che scala automaticamente i pod Laravel in risposta a un picco di traffico, simulando uno scenario di product recall.

### Avviare il load test

In un terminale:

```bash
k6 run scripts/load-test.js
```

Parametri del test:
- **50 utenti virtuali** concorrenti
- **Durata**: 3 minuti
- **Target**: catalogo prodotti e ricerca malfunzionamenti
- **Thresholds**: errori < 5%, latenza p95 < 5 secondi

### Monitorare lo scaling

In un secondo terminale:

```bash
watch -n 5 kubectl get hpa -n techfix
```

Oppure con dettaglio sui pod:

```bash
watch -n 5 kubectl get pods -n techfix -l app=laravel
```

### Comportamento atteso

1. **Scale-up** (~60-90 secondi dall'inizio del carico): il numero di repliche Laravel aumenta da 2 verso il massimo (fino a 10) man mano che la CPU media supera il 70%
2. **Durante il test**: tasso di successo HTTP ≥ 95%, latenza p95 < 5 secondi
3. **Scale-down** (~5-10 minuti dopo la fine del test): le repliche tornano al minimo di 2

### Verificare le query sulla Replica

Prima e dopo il load test, controllare il contatore `Com_select` sulla Replica per confermare che i nuovi pod distribuiscono le letture:

```bash
mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SHOW GLOBAL STATUS LIKE 'Com_select';"
```

---

## Database — Struttura del dump `grp_61_db.sql`

Il dump è esportato da MariaDB 10.4 tramite phpMyAdmin e contiene le seguenti tabelle:

| Tabella | Descrizione | Righe |
|---|---|---|
| `prodotto` | Catalogo prodotti (id, nome, descrizione FULLTEXT, note_tecniche, foto) | 7 |
| `user` | Utenti con ruoli (admin, staff, tecnico) | 7 |
| `malfunzionamento` | Problemi noti associati ai prodotti, con soluzioni | ~10 |
| `centro_assistenza` | Centri di assistenza (nome, indirizzo) | 3 |
| `tecnico` | Profilo tecnico (specializzazione, centro di appartenenza) | — |
| `staff` | Profilo staff (FK a user) | — |
| `accesso_prodotto` | Associazione staff↔prodotto (chiave composita) | 4 |
| `migrations` | Tabella Laravel migrations | 8 |
| `personal_access_tokens` | Tabella Laravel Sanctum | — |

### Credenziali e sicurezza

Il dump originale usa le credenziali di sviluppo definite in `include/connect.php`:

```
$USER = "tweb"
$PASSWORD = "tweb"
```

**Queste credenziali NON devono essere usate in produzione.** Nel deploy cloud-native:

1. L'utente MariaDB `techfix` viene creato con una password sicura (impostata via `DB_PASSWORD`)
2. Le credenziali vengono iniettate nei pod tramite K8s Secrets (`techfix-db-secret`)
3. Il file `include/connect.php` non viene incluso nelle immagini Docker
4. L'APP_KEY Laravel è: `base64:bAcPAEd6NqoIKaPrwKfpMzqvfTb3Qi4tFt65IbGyVM0=`

### Utenti precaricati nel dump

| Username | Password (hash bcrypt nel dump) | Ruolo |
|---|---|---|
| `admin` | `adminadmin` | admin |
| `staff1` | (da dump) | staff |
| `staff2` | (da dump) | staff |
| `staffstaff` | (da dump) | staff |
| `tecnico1` | (da dump) | tecnico |
| `tecnico44` | (da dump) | tecnico |

---

## Sicurezza

- **SecurityContext**: tutti i container eseguono come non-root (UID 1001), filesystem read-only, capabilities dropped
- **NetworkPolicy** (Calico): solo Nginx può raggiungere Laravel; egress da Laravel limitato a MySQL e DNS
- **Firewall iptables**: accesso a MariaDB solo dal pod network k3s
- **K8s Secrets + etcd encryption at rest**: nessuna credenziale in chiaro nei manifest o nelle immagini
- **TLS**: Traefik termina HTTPS con certificato self-signed; redirect HTTP→HTTPS

---

## Comandi utili

```bash
# Stato del cluster
kubectl get all -n techfix

# Log di un pod Laravel
kubectl logs -n techfix -l app=laravel --tail=50

# Shell in un pod Laravel
kubectl exec -it -n techfix deploy/laravel-deployment -- /bin/sh

# Stato replication MariaDB
mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SHOW SLAVE STATUS\G"

# Verifica encryption at rest
sudo bash infra/verify-etcd-encryption.sh

# Rieseguire il deploy dopo modifiche
bash scripts/build-and-import.sh && bash scripts/deploy.sh
```

---

## Note

- Il progetto usa OpenNebula come layer IaaS concettuale (documentato nella relazione del corso). Il deployment reale avviene su una singola VM Ubuntu 24.04.
- k3s sostituisce kubeadm per ridurre l'overhead del control plane su macchina singola.
- MariaDB Primary e Replica girano come processi separati sulla stessa VM — il principio "database fuori dal cluster K8s" è rispettato a livello di isolamento dei processi.
- I pod raggiungono MariaDB tramite l'IP gateway del nodo host nel pod network di k3s (`10.42.0.1`).
