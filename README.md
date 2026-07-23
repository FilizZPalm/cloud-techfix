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

```bash
sudo apt update && sudo apt install -y mariadb-server mariadb-client docker.io curl wget git openssl bc iptables-persistent

# k6 (load testing)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt update && sudo apt install -y k6
```

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
│   └── verify-traefik.sh       # Verifica Traefik Ingress Controller
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
│   ├── full-setup.sh           # ⭐ Script unico — installa tutto
│   ├── build-and-import.sh      # Build Docker + import in k3s containerd
│   ├── create-secrets.sh        # Creazione K8s Secrets (DB, APP, TLS)
│   ├── deploy.sh               # Deploy orchestrato di tutti i manifest
│   └── load-test.js            # k6 script per demo scalabilità
├── tests/
│   ├── smoke/verify-cluster.sh  # 10 smoke tests post-deployment
│   └── integration/             # Test HPA scaling e replication
├── laraProject/                 # Codice sorgente Laravel 10
├── grp_61_db.sql               # Dump database MariaDB
└── README.md
```

---

## Installazione rapida (script unico)

Lo script `full-setup.sh` esegue tutto il setup dall'inizio alla fine in un solo comando:

```bash
cd ~/TechFix-main
export DB_PASSWORD="pippo2002"
export REPL_PASSWORD="pippo2002"
sudo -E bash scripts/full-setup.sh
```

Lo script:
1. Avvia Docker
2. Configura MariaDB Primary (binlog, utenti)
3. Importa il dump `grp_61_db.sql`
4. Configura MariaDB Replica (porta 3307, read-only)
5. Configura la replication Primary → Replica
6. Imposta il firewall iptables
7. Installa k3s con Calico e etcd encryption
8. Installa metrics-server (per HPA)
9. Builda le immagini Docker e le importa in k3s
10. Crea i Kubernetes Secrets
11. Deploya l'intera applicazione (namespace, deployments, services, HPA, ingress, network policies)
12. Genera la cache Laravel e verifica HTTP 200

Al termine, impostare i permessi per kubectl senza sudo:

```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

---

## Installazione passo per passo

Se preferisci eseguire ogni step manualmente per capire cosa succede:

### 0. Prerequisiti runtime

```bash
sudo systemctl start docker
sudo systemctl enable docker
echo "127.0.0.1 techfix.local" | sudo tee -a /etc/hosts
```

### 1. MariaDB Primary

```bash
export DB_PASSWORD="pippo2002"
export REPL_PASSWORD="pippo2002"
sudo -E bash infra/setup-mariadb-primary.sh
```

### 2. Import dump database

```bash
sudo -E bash infra/import-db-dump.sh
```

Verifica:
```bash
sudo mysql -e "SELECT COUNT(*) FROM grp_61_db.prodotto;"
# Atteso: 7
```

### 3. MariaDB Replica

```bash
sudo -E bash infra/setup-mariadb-replica.sh
sudo -E bash infra/setup-mariadb-replication.sh
```

Se i dati non si sono replicati (dump importato prima della replication):
```bash
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SET GLOBAL read_only=0;"
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock grp_61_db < grp_61_db.sql
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SET GLOBAL read_only=1;"
```

Cambiare il bind-address della Replica per accettare connessioni dai pod:
```bash
sudo sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/replica/my.cnf
sudo systemctl restart mariadb-replica
```

Creare l'utente `techfix` sulla Replica:
```bash
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e \
  "CREATE USER IF NOT EXISTS 'techfix'@'%' IDENTIFIED BY 'pippo2002';
   GRANT SELECT ON grp_61_db.* TO 'techfix'@'%'; FLUSH PRIVILEGES;"
```

Verifica:
```bash
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO|Slave_SQL|Seconds_Behind"
```

### 4. Firewall

```bash
sudo bash infra/setup-firewall.sh

# Aggiungere regola per pod network Calico (172.16.0.0/12)
sudo iptables -I INPUT -p tcp -s 172.16.0.0/12 --dport 3306 -j ACCEPT
sudo iptables -I INPUT -p tcp -s 172.16.0.0/12 --dport 3307 -j ACCEPT
```

### 5. k3s + Calico + etcd encryption

```bash
sudo bash infra/setup-k3s.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
kubectl get nodes
# Atteso: nodo Ready
```

### 6. Metrics server

```bash
sudo bash infra/setup-metrics-server.sh
```

### 7. Build immagini Docker

```bash
sudo bash scripts/build-and-import.sh
```

### 8. Kubernetes Secrets

```bash
export DB_PASSWORD="pippo2002"
export DB_PRIMARY_HOST="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
export DB_REPLICA_HOST="${DB_PRIMARY_HOST}"

kubectl apply -f k8s/namespace.yaml
bash scripts/create-secrets.sh
```

### 9. Deploy

```bash
# Aggiorna NetworkPolicy con l'IP corretto del nodo
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
sed -i "s|10.42.0.1/32|${NODE_IP}/32|g" k8s/network-policies.yaml

bash scripts/deploy.sh
```

### 10. Post-deploy fixes

```bash
# Patch liveness probe Nginx (TCP invece di HTTP)
kubectl patch deployment nginx-deployment -n techfix --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe", "value": {"tcpSocket": {"port": 8080}, "initialDelaySeconds": 10, "periodSeconds": 15}},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe", "value": {"tcpSocket": {"port": 8080}, "initialDelaySeconds": 5, "periodSeconds": 10}}
]'

# Genera cache Laravel
kubectl exec -n techfix deployment/laravel-deployment -c laravel -- php artisan config:cache
kubectl exec -n techfix deployment/laravel-deployment -c laravel -- php artisan route:cache
```

---

## Verifica stato del cluster

```bash
# Permessi kubectl (necessario dopo ogni login)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Tutti i pod
kubectl get pods -n techfix

# HPA
kubectl get hpa -n techfix

# Services e Ingress
kubectl get svc,ingress -n techfix

# CPU e memoria per pod
kubectl top pods -n techfix

# Test HTTPS
curl -k https://techfix.local/ -o /dev/null -w "%{http_code}" 2>/dev/null && echo

# Stato replication MariaDB
sudo mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO|Slave_SQL|Seconds_Behind"

# Log pod Laravel
kubectl logs -n techfix -l app=laravel --tail=20

# Log pod Nginx
kubectl logs -n techfix -l app=nginx --tail=20

# NetworkPolicies attive
kubectl get networkpolicy -n techfix

# Secrets (nomi, non valori)
kubectl get secrets -n techfix
```

---

## Demo scalabilità (Product Recall)

La demo mostra l'HPA che scala automaticamente i pod Laravel sotto carico, simulando un product recall con alto traffico.

### Preparazione demo

```bash
# Imposta permessi e KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Velocizza scale-down per la demo (da 5 min a 30s)
kubectl patch hpa laravel-hpa -n techfix --type='json' -p='[
  {"op": "replace", "path": "/spec/behavior/scaleDown/stabilizationWindowSeconds", "value": 30},
  {"op": "replace", "path": "/spec/behavior/scaleDown/policies/0/periodSeconds", "value": 10}
]'

# (Opzionale) Velocizza scale-up per la demo
kubectl patch hpa laravel-hpa -n techfix --type='json' -p='[
  {"op": "replace", "path": "/spec/behavior/scaleUp/stabilizationWindowSeconds", "value": 15},
  {"op": "replace", "path": "/spec/behavior/scaleUp/policies/0/value", "value": 4},
  {"op": "replace", "path": "/spec/behavior/scaleUp/policies/0/periodSeconds", "value": 15}
]'
```

### Terminale 1 — Monitoraggio (ogni secondo)

```bash
watch -n 1 'echo "=== HPA ===" && kubectl get hpa -n techfix && echo "" && echo "=== PODS ===" && kubectl get pods -n techfix -l app=laravel && echo "" && echo "=== CPU per pod ===" && kubectl top pods -n techfix -l app=laravel 2>/dev/null'
```

### Terminale 2 — Load test

```bash
k6 run scripts/load-test.js
```

Parametri: 200 VU, 3 minuti, target `https://techfix.local/` e `https://techfix.local/catalogo`

### Comportamento atteso

| Fase | Tempo | Repliche | CPU |
|---|---|---|---|
| Idle | prima del test | 2 | ~0% |
| Carico | 0-30s | 2→6 | >100% |
| Scaling | 30s-2min | 6→10 | ~80% |
| Fine test | 3min | 10 | scende |
| Scale-down | +30s-1min | 10→2 | ~0% |

### Risultati attesi k6

- ✅ `http_req_failed`: 0% (< 5% threshold)
- ✅ `http_req_duration p(95)`: < 500ms
- ✅ Tutti i checks passed (homepage + catalogo)
- ✅ ~40,000 richieste totali, ~222 req/s
- ✅ HPA scala fino a 10 pod

---

## Database — Struttura del dump

| Tabella | Descrizione | Righe |
|---|---|---|
| `prodotto` | Catalogo prodotti | 7 |
| `user` | Utenti con ruoli (admin, staff, tecnico) | 7 |
| `malfunzionamento` | Problemi noti + soluzioni | ~10 |
| `centro_assistenza` | Centri di assistenza | 3 |
| `tecnico` | Profilo tecnico | — |
| `staff` | Profilo staff | — |
| `accesso_prodotto` | Associazione staff↔prodotto | 4 |

### Credenziali

Il dump usa `tweb`/`tweb` — **non usate in produzione**. Nel cluster:
- L'utente `techfix` viene creato con password sicura (`DB_PASSWORD`)
- Credenziali iniettate via K8s Secrets (`techfix-db-secret`)
- `include/connect.php` non è incluso nelle immagini Docker

---

## Sicurezza

| Misura | Dettaglio |
|---|---|
| Non-root containers | UID 1001, `runAsNonRoot: true` |
| Read-only filesystem | `readOnlyRootFilesystem: true` + emptyDir per /tmp, storage, cache |
| Capabilities dropped | `drop: ["ALL"]`, nessuna capability aggiunta |
| NetworkPolicy (Calico) | Solo Nginx→Laravel:9000, Laravel→MariaDB:3306/3307+DNS |
| Firewall iptables | MariaDB raggiungibile solo da pod network |
| Secrets encryption | etcd encryption at rest con aescbc |
| TLS | Traefik termina HTTPS, redirect HTTP→HTTPS |

---

## Reset completo (per reinstallazione pulita)

```bash
# Rimuovi k3s
sudo /usr/local/bin/k3s-uninstall.sh

# Rimuovi MariaDB Replica
sudo systemctl stop mariadb-replica
sudo systemctl disable mariadb-replica
sudo rm -f /etc/systemd/system/mariadb-replica.service
sudo rm -rf /var/lib/mysql-replica /etc/mysql/replica
sudo systemctl daemon-reload

# Resetta MariaDB Primary
sudo mysql -e "DROP DATABASE IF EXISTS grp_61_db;"
sudo mysql -e "DROP USER IF EXISTS 'techfix'@'%';"
sudo mysql -e "DROP USER IF EXISTS 'repl'@'127.0.0.1';"
sudo rm -f /etc/mysql/mariadb.conf.d/99-primary.cnf
sudo systemctl restart mariadb

# Pulisci Docker
sudo docker system prune -af

# Pulisci hosts e firewall
sudo sed -i '/techfix.local/d' /etc/hosts
sudo iptables -F INPUT
```

---

## Note

- MariaDB gira come servizio systemd sulla VM host (non come StatefulSet in K8s). Scelta architetturale: i DB relazionali classici non si adattano bene al modello Kubernetes per problemi di storage persistente e failover.
- k3s sostituisce kubeadm per ridurre l'overhead del control plane su macchina singola.
- I pod raggiungono MariaDB tramite l'IP del nodo host nel pod network (rilevato automaticamente).
- Lo script `full-setup.sh` è idempotente: può essere rieseguito dopo un reset senza problemi.
