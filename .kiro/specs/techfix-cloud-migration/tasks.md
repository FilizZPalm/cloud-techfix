# Implementation Plan: TechFix Cloud-Native Migration

## Overview

Piano di implementazione per la migrazione di TechFix su una singola VM Azure Ubuntu 24.04 con k3s + MariaDB 10.4.
Stack reale: k3s (Kubernetes), Traefik (Ingress), Calico (NetworkPolicy), MariaDB 10.4 (Primary :3306 + Replica :3307), Docker multi-stage, k6 (load test), PHPUnit (property tests).
Il dump del database esistente (`grp_61_db.sql`) viene importato sul Primary e si replica automaticamente.

## Tasks

- [x] 1. Setup MariaDB Primary sulla VM Azure
  - [x] 1.1 Scrivere `infra/setup-mariadb-primary.sh`
    - Installare `mariadb-server` tramite apt su Ubuntu 24.04
    - Scrivere `/etc/mysql/mariadb.conf.d/99-primary.cnf`: `server-id=1`, `log_bin=mysql-bin`, `binlog_format=ROW`, `bind-address=0.0.0.0`
    - Restartare mariadb e verificare `SHOW MASTER STATUS` restituisce file binlog
    - Creare database `grp_61_db` con charset `utf8mb4 COLLATE utf8mb4_unicode_ci`
    - Creare utente applicativo `techfix`@`%` con password sicura (letta da env var `DB_PASSWORD`)
    - Creare utente replication `repl`@`127.0.0.1` con privilegi `REPLICATION SLAVE`
    - _Requirements: 5.1_

  - [x] 1.2 Importare dump `grp_61_db.sql` sul Primary
    - Copiare `grp_61_db.sql` sulla VM (già presente nel repo: `TechFix-main/grp_61_db.sql`)
    - Eseguire `mysql grp_61_db < grp_61_db.sql` come root
    - Verificare: `SELECT COUNT(*) FROM prodotto` → 7 righe; `SELECT COUNT(*) FROM user` → 7 righe
    - Verificare che l'utente `techfix` possa connettersi e leggere: `mysql -u techfix -p grp_61_db -e "SELECT id,nome FROM prodotto LIMIT 3"`
    - _Requirements: 5.1, 11.1_


- [x] 2. Setup MariaDB Replica sulla VM Azure (seconda istanza porta 3307)
  - [x] 2.1 Scrivere `infra/setup-mariadb-replica.sh`
    - Creare datadir `/var/lib/mysql-replica` con `chown mysql:mysql`
    - Scrivere `/etc/mysql/replica/my.cnf`: `server-id=2`, `read_only=1`, `port=3307`, `socket=/var/run/mysqld/mysqld-replica.sock`, `datadir=/var/lib/mysql-replica`, `bind-address=127.0.0.1`
    - Inizializzare datadir: `mysql_install_db --defaults-file=/etc/mysql/replica/my.cnf --user=mysql`
    - Creare e abilitare servizio systemd `mariadb-replica.service` che esegue `mysqld --defaults-file=/etc/mysql/replica/my.cnf --user=mysql`
    - Avviare il servizio e verificare che ascolti su `127.0.0.1:3307`
    - _Requirements: 5.2, 5.3_

  - [x] 2.2 Configurare replication Primary → Replica
    - Rilevare `MASTER_LOG_FILE` e `MASTER_LOG_POS` da `SHOW MASTER STATUS` sul Primary
    - Sul socket Replica eseguire `CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=3306, MASTER_USER='repl', MASTER_PASSWORD=..., MASTER_LOG_FILE=..., MASTER_LOG_POS=...`
    - Eseguire `START SLAVE` e verificare `SHOW SLAVE STATUS\G`: `Slave_IO_Running: Yes`, `Slave_SQL_Running: Yes`, `Seconds_Behind_Master: 0`
    - Verificare che i dati importati siano presenti sulla Replica: `SELECT COUNT(*) FROM grp_61_db.prodotto` → 7
    - _Requirements: 5.3_

- [x] 3. Configurare firewall iptables per MariaDB
  - [x] 3.1 Scrivere `infra/setup-firewall.sh`
    - Accettare connessioni a porta 3306 e 3307 dal pod network k3s CIDR (`10.42.0.0/16`)
    - Accettare connessioni a porta 3306 e 3307 dal loopback (`127.0.0.1`) per la replication interna
    - Bloccare connessioni a porta 3306 e 3307 da tutti gli altri IP
    - Persistere regole con `iptables-save > /etc/iptables/rules.v4` e installare `iptables-persistent`
    - _Requirements: 8.5, 8.6_


- [x] 4. Setup k3s con Calico e etcd encryption
  - [x] 4.1 Scrivere `infra/setup-k3s.sh` — installazione e configurazione
    - Generare chiave aescbc a 32 byte: `openssl rand -base64 32`
    - Creare `/etc/rancher/k3s/encryption-config.yaml` con provider `aescbc` e la chiave generata
    - Installare k3s con: `--cluster-init`, `--flannel-backend=none`, `--disable-network-policy`, `--kube-apiserver-arg=encryption-provider-config=/etc/rancher/k3s/encryption-config.yaml`
    - Configurare `kubectl`: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`
    - Installare Calico CNI (necessario per NetworkPolicy): `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml`
    - Attendere che il nodo sia in stato `Ready`: polling `kubectl get nodes` entro 5 minuti
    - _Requirements: 2.1, 10.2_

  - [x] 4.2 Installare metrics-server (necessario per HPA)
    - Applicare manifest metrics-server con flag `--kubelet-insecure-tls` per single-node k3s
    - Verificare: `kubectl top nodes` restituisce dati CPU/memoria
    - _Requirements: 6.1_

  - [x] 4.3 Verificare Traefik Ingress Controller
    - Verificare che `kubectl get pods -n kube-system | grep traefik` mostri pod Running
    - Verificare che le porte 80 e 443 siano in ascolto sull'IP pubblico della VM
    - _Requirements: 7.1_

- [x] 5. Checkpoint — Infrastruttura base verificata
  - MariaDB Primary risponde su `127.0.0.1:3306` con dati importati correttamente
  - MariaDB Replica risponde su `127.0.0.1:3307` con `Slave_IO_Running: Yes`
  - k3s nodo in stato `Ready`, Traefik Running, metrics-server Running


- [x] 6. Modificare Laravel — rimuovere `include/connect.php` e usare env vars
  - [x] 6.1 Modificare `laraProject/config/database.php`
    - Rimuovere `require(__DIR__ . '/../../include/connect.php')`
    - Sostituire `$HOST`, `$DB`, `$USER`, `$PASSWORD` con configurazione read/write split da env vars:
      - `read`: `host = env('DB_REPLICA_HOST')`, `port = env('DB_REPLICA_PORT', 3307)`
      - `write`: `host = env('DB_PRIMARY_HOST')`, `port = env('DB_PRIMARY_PORT', 3306)`
      - `sticky = true`, `database = env('DB_DATABASE', 'grp_61_db')`, `username = env('DB_USERNAME')`, `password = env('DB_PASSWORD')`
    - Mantenere `charset = utf8mb4`, `collation = utf8mb4_unicode_ci`, `strict = true`
    - _Requirements: 5.4_

  - [x] 6.2 Modificare `laraProject/app/Exceptions/Handler.php` per HTTP 503
    - Aggiungere `use Illuminate\Database\QueryException;`
    - Nel metodo `render()`: intercettare `QueryException` con `errorInfo[1]` in `[2002, 2003, 2006]`
    - Restituire `response()->json(['error' => 'Service temporarily unavailable'], 503)`
    - Per tutti gli altri casi delegare a `parent::render($request, $exception)`
    - _Requirements: 5.6_


- [x] 7. Dockerfile multi-stage Laravel (PHP-FPM)
  - [x] 7.1 Creare `docker/laravel/Dockerfile` — stage builder
    - Base: `php:8.2-cli` (allineato a PHP 8.2 usato localmente con MariaDB)
    - Installare: `git unzip zip libzip-dev libpng-dev libonig-dev libxml2-dev`
    - Installare estensioni PHP: `pdo_mysql mbstring exif pcntl bcmath gd zip`
    - Copiare Composer da `composer:2.6`
    - Copiare `laraProject/composer.json` e `composer.lock`, eseguire `composer install --no-interaction --no-scripts --no-autoloader`
    - Copiare tutto `laraProject/`, eseguire `composer dump-autoload --optimize --no-dev`
    - **Non copiare** `include/connect.php` nell'immagine (contiene credenziali `tweb`/`tweb`)
    - _Requirements: 3.1_

  - [x] 7.2 Aggiungere stage production al `docker/laravel/Dockerfile`
    - Base: `php:8.2-fpm`
    - Creare gruppo `www` GID 1001, utente `www` UID 1001
    - Copiare da `builder` con `--chown=www:www` (NO Composer, NO PHP-CLI)
    - Creare `storage/logs`, `storage/framework/{cache,sessions,views}`, `bootstrap/cache` con `chown www:www`
    - `USER 1001`, `EXPOSE 9000`, `CMD ["php-fpm"]`
    - _Requirements: 3.1, 9.1_

- [x] 8. Dockerfile Nginx con file statici e nginx.conf
  - [x] 8.1 Creare `docker/nginx/nginx.conf`
    - `listen 8080` (porta ≥1024, no NET_BIND_SERVICE necessaria)
    - Estensioni statiche (`.css .js .png .jpg .gif .webp .svg .ico .woff .woff2 .ttf`): `try_files $uri =404`
    - Location `~ \.php$`: `fastcgi_pass laravel-service:9000`, `fastcgi_read_timeout 60s`
    - Location `/`: `try_files $uri $uri/ /index.php?$query_string`
    - Bloccare `location ~ /\.`: `deny all`
    - `client_max_body_size 10M`
    - _Requirements: 4.3, 4.4, 4.6_

  - [x] 8.2 Creare `docker/nginx/Dockerfile`
    - Base: `nginx:1.25-alpine`
    - Creare gruppo/utente `nginx-app` GID/UID 1001
    - Copiare `nginx.conf` in `/etc/nginx/conf.d/default.conf`
    - Copiare `laraProject/public` in `/var/www/html/public` con `--chown=nginx-app:nginx-app`
    - Adattare `nginx.conf` principale: `user nginx-app; pid /tmp/nginx.pid;`
    - `USER 1001`, `EXPOSE 8080`
    - _Requirements: 3.2, 9.1_


- [x] 9. Build immagini Docker e import in k3s
  - [x] 9.1 Scrivere `scripts/build-and-import.sh`
    - Build immagine Laravel: `docker build -f docker/laravel/Dockerfile -t techfix/laravel-app:1.0.0 .`
    - Verificare dimensione: `docker image ls techfix/laravel-app` — avviso se > 500MB
    - Build immagine Nginx: `docker build -f docker/nginx/Dockerfile -t techfix/nginx:1.0.0 .`
    - Importare in k3s (usa containerd, non Docker daemon):
      - `docker save techfix/laravel-app:1.0.0 | sudo k3s ctr images import -`
      - `docker save techfix/nginx:1.0.0 | sudo k3s ctr images import -`
    - Verificare: `sudo k3s ctr images list | grep techfix`
    - _Requirements: 3.1, 3.2, 3.3_

- [x] 10. Kubernetes manifest — Namespace, ConfigMaps, Services
  - [x] 10.1 Creare `k8s/namespace.yaml`
    - `Namespace` con `name: techfix`, label `kubernetes.io/metadata.name: techfix`
    - _Requirements: 4.1, 4.2_

  - [x] 10.2 Creare `k8s/configmaps/nginx-config.yaml`
    - `ConfigMap` `nginx-config` nel namespace `techfix`
    - Contenuto di `docker/nginx/nginx.conf` come data entry `default.conf`
    - _Requirements: 4.3, 4.4_

  - [x] 10.3 Creare `k8s/services.yaml`
    - `nginx-service`: ClusterIP, port 80 → targetPort 8080
    - `laravel-service`: ClusterIP, port 9000 → targetPort 9000
    - Entrambi nel namespace `techfix`
    - _Requirements: 4.1, 4.2_


- [x] 11. Kubernetes manifest — Deployments con SecurityContext
  - [x] 11.1 Creare `k8s/laravel-deployment.yaml`
    - `Deployment` `laravel-deployment`, namespace `techfix`, `replicas: 2`
    - Pod securityContext: `runAsNonRoot: true`, `runAsUser: 1001`, `fsGroup: 1001`
    - Container `laravel`: image `techfix/laravel-app:1.0.0`, port 9000
    - resources: requests `cpu: 250m, memory: 256Mi`; limits `cpu: 500m, memory: 512Mi`
    - `envFrom`: `secretRef techfix-db-secret` e `secretRef techfix-app-secret`
    - Container securityContext: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`
    - volumeMounts: `laravel-storage` → `/var/www/html/storage`, `laravel-cache` → `/var/www/html/bootstrap/cache`
    - volumes: entrambi `emptyDir: {}`
    - livenessProbe e readinessProbe su `tcpSocket port: 9000`
    - _Requirements: 4.2, 9.1, 9.2, 9.3, 9.4, 9.6_

  - [x] 11.2 Creare `k8s/nginx-deployment.yaml`
    - `Deployment` `nginx-deployment`, namespace `techfix`, `replicas: 1`
    - Pod securityContext: `runAsNonRoot: true`, `runAsUser: 1001`, `fsGroup: 1001`
    - Container `nginx`: image `techfix/nginx:1.0.0`, port 8080
    - Container securityContext: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` (nessuna capability aggiunta — porta 8080 ≥ 1024)
    - volumeMounts: `nginx-cache` → `/var/cache/nginx`, `nginx-run` → `/var/run`, `nginx-config` → `/etc/nginx/conf.d` (da ConfigMap)
    - volumes: `nginx-cache` e `nginx-run` emptyDir, `nginx-config` da ConfigMap
    - livenessProbe: httpGet path `/` port 8080
    - _Requirements: 4.1, 9.1, 9.2, 9.4, 9.5_


- [x] 12. Kubernetes manifest — HPA e Ingress
  - [x] 12.1 Creare `k8s/laravel-hpa.yaml`
    - `HorizontalPodAutoscaler` v2, `laravel-hpa`, namespace `techfix`
    - `scaleTargetRef`: `laravel-deployment`, `minReplicas: 2`, `maxReplicas: 10`
    - Metrica: `cpu averageUtilization: 70`
    - behavior scaleDown: `stabilizationWindowSeconds: 300`, policy 1 replica/60s
    - behavior scaleUp: `stabilizationWindowSeconds: 60`, policy 2 repliche/60s
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x] 12.2 Creare `k8s/ingress.yaml` per Traefik
    - `Ingress` `techfix-ingress`, namespace `techfix`, `ingressClassName: traefik`
    - Annotations: `traefik.ingress.kubernetes.io/router.entrypoints: websecure`, `router.tls: "true"`
    - tls: host `techfix.local`, `secretName: techfix-tls-secret`
    - Rule: host `techfix.local`, path `/` → `nginx-service:80`
    - _Requirements: 7.1, 7.2, 7.3_

- [x] 13. Kubernetes Secrets e EncryptionConfiguration
  - [x] 13.1 Scrivere `scripts/create-secrets.sh`
    - Lo script legge credenziali da env vars (`DB_PASSWORD`, `APP_KEY`, etc.)
    - Creare `techfix-db-secret` con: `DB_PRIMARY_HOST`, `DB_PRIMARY_PORT=3306`, `DB_REPLICA_HOST`, `DB_REPLICA_PORT=3307`, `DB_DATABASE=grp_61_db`, `DB_USERNAME=techfix`, `DB_PASSWORD`
    - Creare `techfix-app-secret` con: `APP_KEY=base64:bAcPAEd6NqoIKaPrwKfpMzqvfTb3Qi4tFt65IbGyVM0=`, `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://techfix.local`
    - Generare certificato self-signed e creare `techfix-tls-secret` con `kubectl create secret tls`
    - Tutti i secret nel namespace `techfix`
    - _Requirements: 10.1, 10.3, 10.5_

  - [x] 13.2 Verificare etcd encryption at rest
    - Dopo l'installazione k3s con EncryptionConfiguration, creare un Secret di test
    - Verificare con `sudo k3s etcd-snapshot` che i dati siano cifrati
    - _Requirements: 10.2_


- [x] 14. NetworkPolicy Kubernetes (con Calico)
  - [x] 14.1 Creare `k8s/network-policies.yaml`
    - Policy `allow-nginx-to-laravel`: ingress su Laravel da `podSelector app: nginx` porta 9000
    - Policy `laravel-egress-policy`: egress da Laravel verso `10.42.0.1/32` (nodo host) porte 3306 e 3307, e DNS porta 53 UDP/TCP
    - Policy `allow-ingress-to-nginx`: ingress su Nginx da `namespaceSelector kube-system` porta 8080
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 15. Script di deploy orchestrato
  - [x] 15.1 Scrivere `scripts/deploy.sh`
    - Rilevare IP nodo host k3s nel pod network: `NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')`
    - Applicare in ordine: namespace → configmaps → network-policies → deployments → services → hpa → ingress
    - Polling su `kubectl rollout status` per `laravel-deployment` e `nginx-deployment`
    - Output finale: `kubectl get all -n techfix`
    - _Requirements: 4.1, 4.2, 6.1, 7.1_

- [x] 16. Checkpoint — Container e manifest verificati
  - Build Docker OK, immagini importate in k3s, manifest applicati senza errori, pod Running, Secrets creati


- [x] 17. Test regressione funzionalità Laravel
  - [x]* 17.1 Scrivere `tests/property/AuthRedirectPropertyTest.php` (Property 11)
    - **Property 11: Tutte le rotte protette redirezionano utenti non autenticati con HTTP 302**
    - **Validates: Requirements 11.6**
    - Iterare su tutte le rotte con middleware `auth`; verificare HTTP 302 → `/login` senza dati riservati

  - [x]* 17.2 Scrivere `tests/property/FileUploadPropertyTest.php` (Property 12)
    - **Property 12: File non-immagine rifiutati con HTTP 422, senza salvataggio**
    - **Validates: Requirements 11.7**
    - Generare 100 file con estensioni non-immagine; autenticarsi come `staff1`; verificare HTTP 422 e assenza in storage

  - [x]* 17.3 Scrivere unit test CRUD base
    - `tests/Feature/TecnicoTest.php`: GET catalogo → 200, GET dettaglio prodotto → malfunzionamenti presenti
    - `tests/Feature/StaffTest.php`: POST/PUT/DELETE malfunzionamento → 200 o 302
    - `tests/Feature/AdminTest.php`: CRUD utenti, centri, assegnazioni → 200 o 302
    - _Requirements: 11.1, 11.2, 11.3_

- [x] 18. Script load test k6 per demo Product Recall
  - [x] 18.1 Scrivere `scripts/load-test.js` (k6)
    - `options.vus: 50`, `options.duration: '3m'`
    - Target: GET `/` (catalogo), GET con ricerca AJAX (malfunzionamenti) su `https://techfix.local`
    - Thresholds: `http_req_failed < 0.05`, `http_req_duration p(95) < 5000`
    - _Requirements: 12.1, 12.4_

  - [x]* 18.2 Scrivere `tests/integration/test-hpa-scaling.sh`
    - Avviare `k6 run scripts/load-test.js` in background
    - Polling ogni 15s su `kubectl get hpa laravel-hpa -n techfix`
    - Verificare entro 90s che `REPLICAS > 2`
    - Verificare `http_req_failed < 5%` nell'output k6
    - Dopo stop: polling fino a 10 minuti per scale-down a `REPLICAS = 2`
    - _Requirements: 12.2, 12.3, 12.4_

  - [x]* 18.3 Verificare incremento `Com_select` su MariaDB Replica durante load test (Property 13)
    - **Property 13: HPA replica count ∈ [2, 10] durante tutto il load test**
    - **Validates: Requirements 6.4, 12.5**
    - Registrare 100 snapshot di `REPLICAS` durante load test; verificare tutti ∈ [2, 10]
    - Prima e dopo load test: `mysql --socket=/var/run/mysqld/mysqld-replica.sock -e "SHOW GLOBAL STATUS LIKE 'Com_select'"` — verificare incremento


- [x] 19. Smoke tests e verifica post-deployment
  - [x] 19.1 Scrivere `tests/smoke/verify-cluster.sh`
    - ST-01: MariaDB Primary risponde su `127.0.0.1:3306` e contiene 7 prodotti
    - ST-02: MariaDB Replica risponde su `127.0.0.1:3307`, `Slave_IO_Running: Yes`
    - ST-03: `kubectl get nodes` → nodo in stato `Ready`
    - ST-04: Traefik pod Running, porte 80/443 in ascolto
    - ST-05: `openssl s_client -connect techfix.local:443` → certificato TLS presente
    - ST-06: `curl -v http://techfix.local/` → 301 redirect a https
    - ST-07: `curl -k https://techfix.local/` → HTTP 200
    - ST-08: `kubectl exec -n techfix deploy/laravel-deployment -- id` → `uid=1001`
    - ST-09: `kubectl exec -n techfix deploy/laravel-deployment -- curl -v http://8.8.8.8 --max-time 3` → bloccato (NetworkPolicy)
    - ST-10: `kubectl get secret techfix-db-secret -n techfix -o yaml` → valori base64, non in chiaro
    - _Requirements: 2.1, 5.1, 7.2, 7.3, 8.4, 9.1, 10.1_

  - [x]* 19.2 Scrivere `tests/integration/test-mariadb-replication.sh`
    - IT-01: INSERT su Primary → `Seconds_Behind_Master ≤ 5` su Replica
    - IT-02: INSERT diretto su Replica → errore `read-only`
    - IT-03: Simulare Replica down (stop `mariadb-replica`) → query Laravel continuano senza errori HTTP
    - IT-04: Riavviare Replica → replication riprende automaticamente
    - _Requirements: 5.2, 5.3, 5.5_

- [x] 20. README e documentazione
  - [x] 20.1 Creare `README.md` principale
    - Prerequisiti: `mariadb-server`, `k3s`, `docker`, `k6`, `kubectl`
    - Istruzioni step-by-step: setup MariaDB → import dump → k3s → build Docker → deploy → verifica
    - Sezione "Demo scalabilità": comandi k6 + `watch kubectl get hpa`
    - Note sulla struttura del dump `grp_61_db.sql` e credenziali da impostare
    - _Requirements: 12.1_

- [x] 21. Checkpoint finale — tutti i test non-opzionali passano
  - Smoke tests ST-01..ST-10 tutti verdi
  - Pod Laravel e Nginx Running, HPA attivo, Traefik TLS funzionante
  - MariaDB Primary + Replica in replication con dati `grp_61_db` importati correttamente



## Notes

- I task con `*` sono opzionali (property-based tests e integration tests avanzati) — saltabili per un MVP rapido
- Il dump `grp_61_db.sql` contiene credenziali hash bcrypt reali — le password originali (`tweb`) vanno cambiate sulla VM Azure
- Il file `include/connect.php` con `$PASSWORD="tweb"` non deve mai entrare nell'immagine Docker (Task 7.1)
- L'APP_KEY `base64:bAcPAEd6NqoIKaPrwKfpMzqvfTb3Qi4tFt65IbGyVM0=` è già pronta per essere inserita nel Secret
- Il pod network di k3s usa `10.42.0.0/16` — i pod raggiungono MariaDB tramite `10.42.0.1` (gateway nodo host)

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "4.1"] },
    { "id": 1, "tasks": ["1.2", "4.2", "4.3"] },
    { "id": 2, "tasks": ["2.1", "3.1", "6.1", "7.1", "8.1"] },
    { "id": 3, "tasks": ["2.2", "6.2", "7.2", "8.2", "10.1", "10.2", "10.3"] },
    { "id": 4, "tasks": ["9.1", "11.1", "11.2", "12.1", "12.2", "13.1", "14.1"] },
    { "id": 5, "tasks": ["13.2", "15.1"] },
    { "id": 6, "tasks": ["17.1", "17.2", "17.3", "18.1", "19.1", "20.1"] },
    { "id": 7, "tasks": ["18.2", "18.3", "19.2"] }
  ]
}
```
