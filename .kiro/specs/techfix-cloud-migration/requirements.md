# Requirements Document

## Introduction

Questo documento definisce i requisiti per la migrazione cloud-native di TechFix, un'applicazione web monolitica Laravel 10 che gestisce l'assistenza tecnica post-vendita. Il progetto è sviluppato per il corso universitario di Cloud Computing.

L'obiettivo è trasformare il monolite esistente in un sistema containerizzato, orchestrato da Kubernetes su infrastruttura OpenNebula, con scalabilità orizzontale automatica, replica del database e hardening della sicurezza. La migrazione deve preservare integralmente tutte le funzionalità applicative esistenti (catalogo prodotti, gestione malfunzionamenti, area tecnici, area staff, area amministratore).

## Glossary

- **Sistema**: L'intera piattaforma TechFix cloud-native risultante dalla migrazione
- **OpenNebula**: Piattaforma IaaS che esegue il provisioning delle VM sottostanti
- **Kubernetes**: Orchestratore di container che gestisce il ciclo di vita dei pod applicativi
- **Laravel_App**: Il container applicativo che esegue PHP-FPM con la business logic di TechFix
- **Nginx_Pod**: Il container che riceve il traffico esterno, serve file statici e fa da reverse proxy verso Laravel_App
- **Ingress_Controller**: Il componente Kubernetes che termina TLS e instrada il traffico HTTPS verso i servizi interni
- **HPA**: Horizontal Pod Autoscaler di Kubernetes, responsabile dello scaling automatico dei pod Laravel_App
- **MySQL_Primary**: L'istanza MySQL su VM OpenNebula dedicata, che riceve tutte le operazioni di scrittura
- **MySQL_Replica**: L'istanza MySQL su VM OpenNebula dedicata, sincronizzata da MySQL_Primary, che serve le operazioni di lettura
- **NetworkPolicy**: Risorsa Kubernetes che definisce le regole di isolamento del traffico pod-to-pod
- **SecurityContext**: Configurazione Kubernetes che applica le restrizioni di privilegio ai container
- **K8s_Secrets**: Risorsa Kubernetes che memorizza i dati sensibili in forma crittografata
- **etcd**: Datastore distribuito del control plane Kubernetes che conserva lo stato del cluster
- **VM**: Macchina virtuale fornita da OpenNebula
- **Worker_Node**: VM OpenNebula che ospita i pod applicativi Kubernetes
- **Master_Node**: VM OpenNebula che ospita il control plane Kubernetes
- **Load_Generator**: Strumento esterno che simula traffico HTTP concorrente per il test di scalabilità
- **Tecnico**: Utente che accede a TechFix per consultare malfunzionamenti e soluzioni
- **Staff**: Utente che gestisce la base di conoscenza tecnica (malfunzionamenti, soluzioni, prodotti)
- **Amministratore**: Utente che gestisce account, centri di assistenza e assegnazioni prodotti

---

## Requirements

---

### Requisito 1: Provisioning dell'Infrastruttura con OpenNebula

**User Story:** Come operatore di sistema, voglio che tutte le VM necessarie siano provisioniate tramite OpenNebula, in modo da avere un layer IaaS riproducibile e separato dall'orchestrazione applicativa.

#### Criteri di Accettazione

1. WHEN il provisioning di una VM Master_Node viene avviato tramite OpenNebula, THEN THE Sistema SHALL riportare lo stato della VM come RUNNING entro 5 minuti, confermando che il control plane Kubernetes può essere installato su di essa
2. WHEN il provisioning di due VM Worker_Node viene avviato tramite OpenNebula, THEN THE Sistema SHALL riportare lo stato di entrambe le VM come RUNNING entro 5 minuti, confermando che possono ospitare pod applicativi
3. WHEN il provisioning di una VM dedicata a MySQL_Primary viene avviato tramite OpenNebula, THEN THE Sistema SHALL riportare lo stato della VM come RUNNING entro 5 minuti, separata dalla rete interna del cluster Kubernetes
4. WHEN il provisioning di una VM dedicata a MySQL_Replica viene avviato tramite OpenNebula, THEN THE Sistema SHALL riportare lo stato della VM come RUNNING entro 5 minuti, separata dalla rete interna del cluster Kubernetes
5. WHEN il provisioning di una VM fallisce, THEN THE Sistema SHALL registrare il codice di errore OpenNebula, eliminare tutte le risorse VM parzialmente create in quella sessione di provisioning, e terminare il processo di provisioning senza ulteriori tentativi automatici
6. WHEN tutte le VM sono in stato RUNNING, THEN THE Sistema SHALL dimostrare la connettività di rete tra ogni coppia di VM tramite ping bidirezionale sulla rete virtuale OpenNebula condivisa

---

### Requisito 2: Cluster Kubernetes su VM OpenNebula

**User Story:** Come operatore di sistema, voglio un cluster Kubernetes funzionante installato sulle VM OpenNebula, in modo da poter orchestrare i container applicativi.

#### Criteri di Accettazione

1. WHEN l'installazione del control plane Kubernetes sul Master_Node viene avviata, THEN THE Sistema SHALL completare l'inizializzazione con `kubeadm init` (o equivalente) riportando lo stato del Master_Node come `Ready` nel output di `kubectl get nodes` entro 10 minuti
2. WHEN il comando di join viene eseguito su un Worker_Node, THEN THE Worker_Node SHALL apparire con stato `Ready` nell'output di `kubectl get nodes` sul Master_Node entro 5 minuti; IF il join fallisce, THEN THE Sistema SHALL restituire il messaggio di errore kubeadm senza modificare la configurazione del cluster esistente
3. WHEN un Worker_Node risulta in stato `NotReady` per più di 5 minuti, THEN THE Kubernetes SHALL ricollocare tutti i pod in stato `Running` ospitati su quel nodo su un Worker_Node con stato `Ready`, portando a termine la rescheduling entro 10 minuti dalla rilevazione
4. WHILE almeno due Worker_Node sono in stato `Ready` nel cluster, THE Sistema SHALL mantenere almeno 2 repliche di Laravel_App in stato `Running` come definito dalla specifica del Deployment
5. IF l'installazione del control plane Kubernetes sul Master_Node fallisce, THEN THE Sistema SHALL restituire il codice di uscita non-zero di kubeadm e lasciare il Master_Node in uno stato ripristinabile tramite `kubeadm reset`
6. IF un Worker_Node non raggiunge lo stato `Ready` entro 5 minuti dal comando di join, THEN THE Sistema SHALL registrare i log di kubelet del nodo e non aggiungere il nodo al pool di scheduling del cluster

---

### Requisito 3: Build Docker Multi-Stage per i Container Applicativi

**User Story:** Come sviluppatore, voglio che le immagini Docker siano costruite tramite build multi-stage, in modo da ottenere immagini di produzione compatte, prive di dipendenze di build.

#### Criteri di Accettazione

1. WHEN il Dockerfile di Laravel_App viene eseguito con `docker build`, THEN THE Sistema SHALL produrre un'immagine in due stage: il primo stage (`builder`) installa le dipendenze PHP tramite Composer includendo le dipendenze di sviluppo, il secondo stage (`production`) copia solo i file dell'applicazione e la directory `vendor/` nel secondo stage senza includere Composer, PHP-CLI, o altre dipendenze di build; l'immagine finale SHALL essere basata su `php:8.x-fpm` o derivato
2. WHEN il Dockerfile di Nginx_Pod viene eseguito con `docker build`, THEN THE Sistema SHALL produrre un'immagine che include la configurazione nginx.conf per il reverse proxy verso PHP-FPM e i file statici dell'applicazione (CSS, JS, immagini) copiati dalla directory `public/` di Laravel nella document root di Nginx
3. WHEN il comando `docker build` per Laravel_App termina con successo, IF la dimensione dell'immagine risultante supera 500 MB secondo `docker image ls`, THEN THE Sistema SHALL stampare un messaggio di avviso esplicito nello stdout del processo di build prima della riga `Successfully built`
4. WHEN due build successive di Laravel_App vengono eseguite dallo stesso commit git con lo stesso Dockerfile senza modifiche ai file sorgente, THEN entrambe le immagini SHALL rispondere con lo stesso output HTTP a una richiesta GET `/` su un container avviato localmente, confermando l'equivalenza funzionale

---

### Requisito 4: Deployment dei Pod Applicativi in Kubernetes

**User Story:** Come operatore di sistema, voglio che Nginx e Laravel siano deployati come pod Kubernetes separati, in modo da poterli scalare e gestire indipendentemente.

#### Criteri di Accettazione

1. THE Sistema SHALL deployare Nginx_Pod come Deployment Kubernetes con almeno 1 replica; WHEN il Deployment viene applicato con `kubectl apply`, THEN il pod Nginx_Pod SHALL raggiungere lo stato `Running` con `READY 1/1` entro 2 minuti
2. THE Sistema SHALL deployare Laravel_App come Deployment Kubernetes separato da Nginx_Pod; WHEN il Deployment viene applicato, THEN il pod Laravel_App SHALL essere in ascolto sulla porta 9000 in modalità FastCGI (PHP-FPM) e raggiungere lo stato `Running` con `READY 1/1` entro 2 minuti
3. WHEN una richiesta HTTP verso un URI che termina in `.php` o che non corrisponde a nessun file statico noto arriva a Nginx_Pod, THEN THE Nginx_Pod SHALL inoltrarla a Laravel_App tramite FastCGI sulla porta 9000 e restituire la risposta al client
4. WHEN una richiesta HTTP verso un URI con estensione `.css`, `.js`, `.png`, `.jpg`, `.gif`, `.webp`, `.svg`, `.ico`, `.woff`, `.woff2`, o `.ttf` arriva a Nginx_Pod, THEN THE Nginx_Pod SHALL servire il file direttamente dalla propria document root senza contattare Laravel_App; IF il file statico richiesto non esiste nella document root, THEN THE Nginx_Pod SHALL restituire HTTP 404 senza contattare Laravel_App
5. WHEN un pod Laravel_App esce con codice non-zero o fallisce la liveness probe, THEN THE Kubernetes SHALL avviare un nuovo pod Laravel_App entro 30 secondi; IF il pod non raggiunge lo stato `Running` dopo 3 tentativi di restart consecutivi, THEN THE Kubernetes SHALL portare il pod in stato `CrashLoopBackOff` e registrare l'evento nei log di sistema
6. WHEN la comunicazione FastCGI tra Nginx_Pod e Laravel_App supera il timeout configurato (default: 60 secondi), THEN THE Nginx_Pod SHALL restituire al client una risposta HTTP 504 Gateway Timeout senza terminare il processo Nginx

---

### Requisito 5: Database MySQL su VM OpenNebula con Read Replica

**User Story:** Come architetto del sistema, voglio che MySQL Primary e Replica girino su VM OpenNebula dedicate fuori dal cluster Kubernetes, in modo da garantire stabilità dello storage e separazione degli workload di lettura e scrittura.

#### Criteri di Accettazione

1. THE MySQL_Primary SHALL accettare operazioni di lettura e scrittura dai pod Laravel_App; WHEN una query di scrittura (INSERT, UPDATE, DELETE) viene eseguita tramite Laravel_App, THEN THE MySQL_Primary SHALL confermare il commit della transazione al pod chiamante
2. WHEN MySQL_Replica riceve una query di scrittura (INSERT, UPDATE, DELETE) direttamente da un pod Laravel_App, THEN THE MySQL_Replica SHALL rifiutare la query con l'errore MySQL `ER_SLAVE_NOT_RUNNING` o equivalente `read-only` error, senza eseguire la modifica
3. WHEN MySQL_Primary riceve un'operazione di scrittura confermata, THEN THE MySQL_Primary SHALL replicare la modifica su MySQL_Replica tramite MySQL native binary log replication entro 5 secondi; la latenza di replica è verificabile tramite il campo `Seconds_Behind_Master` di `SHOW SLAVE STATUS` sul server MySQL_Replica
4. THE Laravel_App SHALL instradare le query di lettura verso MySQL_Replica e le query di scrittura verso MySQL_Primary, utilizzando la configurazione `read/write split` nativa di Laravel nel file `config/database.php` con i parametri `read` e `write`
5. IF MySQL_Replica diventa irraggiungibile dalla rete dei Worker_Node, THEN THE Laravel_App SHALL instradare tutte le query, incluse quelle di lettura, verso MySQL_Primary senza restituire errori alle richieste HTTP in corso
6. IF MySQL_Primary diventa irraggiungibile dalla rete dei Worker_Node, THEN THE Laravel_App SHALL restituire HTTP 503 alle richieste che richiedono operazioni di scrittura sul database; le richieste che richiedono solo lettura SHALL continuare ad essere servite tramite MySQL_Replica

---

### Requisito 6: Scalabilità Orizzontale con Kubernetes HPA

**User Story:** Come operatore di sistema, voglio che i pod Laravel_App scalino automaticamente in base al carico CPU, in modo da gestire picchi di traffico come un product recall senza intervento manuale.

#### Criteri di Accettazione

1. THE HPA SHALL monitorare l'utilizzo CPU medio di tutti i pod Laravel_App attivi nel Deployment; la metrica CPU è calcolata come percentuale del `cpu` request definito nel container spec del Deployment di Laravel_App
2. WHEN l'utilizzo CPU medio dei pod Laravel_App supera il 70% del CPU request per almeno 1 minuto, THE HPA SHALL incrementare il numero di repliche di Laravel_App di almeno 1 unità per ciclo di scaling
3. WHEN l'utilizzo CPU medio dei pod Laravel_App scende sotto il 30% del CPU request per almeno 5 minuti consecutivi, THE HPA SHALL decrementare il numero di repliche di Laravel_App di almeno 1 unità per ciclo di scaling verso il valore minimo configurato
4. THE HPA SHALL mantenere il numero di repliche di Laravel_App tra un minimo di 2 e un massimo di 10; WHEN il numero di repliche attive raggiunge 10 e l'utilizzo CPU medio rimane sopra il 70%, THEN THE HPA SHALL non aggiungere ulteriori repliche e SHALL registrare l'evento `FailedGetScale` o equivalente nel log degli eventi Kubernetes
5. WHEN il Load_Generator genera traffico concorrente equivalente a 50 richieste simultanee verso gli endpoint di catalogo e malfunzionamenti per almeno 2 minuti, THE HPA SHALL aumentare il numero di repliche di Laravel_App a un valore superiore al minimo configurato entro 90 secondi dall'inizio sostenuto del picco di carico
6. WHEN il Load_Generator interrompe il traffico di picco e l'utilizzo CPU medio scende sotto il 30%, THE HPA SHALL ridurre le repliche di Laravel_App al valore minimo di 2 entro 10 minuti dall'abbassamento del carico

---

### Requisito 7: Ingress Controller con Terminazione TLS

**User Story:** Come utente finale, voglio accedere a TechFix esclusivamente tramite HTTPS, in modo da avere le comunicazioni cifrate tra browser e cluster.

#### Criteri di Accettazione

1. THE Ingress_Controller SHALL terminare le connessioni TLS in ingresso sulla porta 443 e instradare il traffico decrittato verso il Service Kubernetes di Nginx_Pod sulla porta 80 interna al cluster
2. WHEN un client effettua una richiesta HTTP sulla porta 80 verso l'Ingress_Controller, THEN THE Ingress_Controller SHALL rispondere con HTTP 301 e header `Location` che punta all'URL equivalente su porta 443
3. WHEN un client avvia un handshake TLS verso l'Ingress_Controller, THEN THE Ingress_Controller SHALL presentare il certificato TLS configurato (anche self-signed) per il dominio target, rendendo il campo `Subject` del certificato verificabile tramite `openssl s_client`
4. IF il certificato TLS configurato sull'Ingress_Controller è assente o non caricabile al momento dell'handshake, THEN THE Ingress_Controller SHALL terminare il handshake TLS con un alert `handshake_failure` e registrare un errore nei propri log con livello ERROR
5. IF il certificato TLS configurato sull'Ingress_Controller risulta scaduto (data `NotAfter` precedente alla data corrente), THEN THE Ingress_Controller SHALL completare il handshake TLS presentando il certificato scaduto e registrare un avviso nei propri log con livello WARN, lasciando al client la decisione di rifiutare la connessione

---

### Requisito 8: Network Policy per l'Isolamento del Traffico

**User Story:** Come responsabile della sicurezza, voglio che le NetworkPolicy Kubernetes limitino le comunicazioni tra i componenti ai soli flussi necessari, in modo da ridurre la superficie di attacco in caso di compromissione di un pod.

#### Criteri di Accettazione

1. WHEN una NetworkPolicy viene applicata al namespace dell'applicazione, THEN THE NetworkPolicy SHALL consentire traffico in ingresso verso i pod Laravel_App esclusivamente dai pod con label corrispondente a Nginx_Pod nello stesso namespace, verificabile tramite `kubectl describe networkpolicy`
2. IF un pod che non ha la label di Nginx_Pod tenta di aprire una connessione TCP verso un pod Laravel_App sulla porta 9000, THEN THE NetworkPolicy SHALL bloccare la connessione con un reset o drop del pacchetto, senza che Laravel_App riceva la richiesta
3. WHEN una NetworkPolicy di egress viene applicata ai pod Laravel_App, THEN THE NetworkPolicy SHALL consentire traffico in uscita da Laravel_App verso MySQL_Primary e MySQL_Replica sulla porta 3306 e verso il DNS interno del cluster sulla porta 53 (TCP e UDP)
4. IF un pod Laravel_App tenta di aprire una connessione TCP verso un indirizzo esterno diverso da MySQL_Primary, MySQL_Replica e dal DNS del cluster (porta 53), THEN THE NetworkPolicy SHALL bloccare la connessione; il tentativo SHALL essere verificabile tramite `kubectl exec` e un comando `curl` o `nc` dall'interno del pod
5. WHEN una regola firewall viene configurata sulle VM MySQL_Primary e MySQL_Replica (tramite `iptables` o equivalente), THEN THE firewall SHALL accettare connessioni in ingresso sulla porta 3306 esclusivamente dagli indirizzi IP dei Worker_Node del cluster Kubernetes, identificati tramite il CIDR della rete virtuale OpenNebula dei Worker_Node
6. WHEN una regola firewall di egress viene configurata sulle VM MySQL_Primary e MySQL_Replica, THEN THE firewall SHALL bloccare tutto il traffico in uscita verso Internet (destinazioni esterne alla rete virtuale OpenNebula), consentendo solo il traffico verso indirizzi interni alla stessa rete virtuale OpenNebula (replication tra Primary e Replica inclusa)
7. WHEN la replication MySQL tra MySQL_Primary e MySQL_Replica è attiva, THEN THE NetworkPolicy e le regole firewall delle VM SHALL consentire il traffico di replication MySQL sulla porta 3306 da MySQL_Primary verso MySQL_Replica, verificabile tramite `SHOW SLAVE STATUS` su MySQL_Replica

---

### Requisito 9: Container Hardening tramite SecurityContext

**User Story:** Come responsabile della sicurezza, voglio che tutti i container applicativi operino con il minimo privilegio necessario, in modo da limitare l'impatto di una vulnerabilità applicativa sfruttata da un attaccante.

#### Criteri di Accettazione

1. THE SecurityContext SHALL configurare tutti i container (Nginx_Pod e Laravel_App) con `runAsNonRoot: true` e `runAsUser` impostato a un valore nell'intervallo 1001–65535; WHEN il pod viene avviato, THEN `kubectl exec -- id` SHALL riportare un UID corrispondente al valore configurato, diverso da 0
2. THE SecurityContext SHALL montare il filesystem radice di tutti i container con `readOnlyRootFilesystem: true`; WHEN un processo nel container tenta di scrivere in una directory non esplicitamente montata come scrivibile, THEN il sistema operativo SHALL restituire `Read-only file system` al processo
3. WHERE Laravel_App richiede scrittura su disco, THE SecurityContext SHALL montare le directory `storage/` e `bootstrap/cache/` tramite volume di tipo `emptyDir` o PersistentVolumeClaim con accesso in scrittura; nessun'altra directory SHALL avere un volume scrivibile montato sopra il filesystem read-only
4. THE SecurityContext SHALL configurare `capabilities.drop: ["ALL"]` su tutti i container (Nginx_Pod e Laravel_App); nessuna capability SHALL essere aggiunta al container Laravel_App tramite `capabilities.add`
5. IF Nginx_Pod è configurato per ascoltare su una porta inferiore a 1024, THEN THE SecurityContext SHALL aggiungere esclusivamente la capability `NET_BIND_SERVICE` tramite `capabilities.add: ["NET_BIND_SERVICE"]` al container Nginx_Pod; se Nginx è configurato su porta ≥ 1024, THEN nessuna capability SHALL essere aggiunta
6. THE SecurityContext SHALL impostare `allowPrivilegeEscalation: false` su tutti i container; WHEN un processo all'interno di un container tenta di eseguire un binario con bit setuid, THEN il kernel SHALL ignorare il bit setuid e il processo SHALL mantenere il UID del processo chiamante
7. WHEN un processo all'interno di un container tenta di eseguire una syscall che richiede una capability non presente nel set del container, THEN il kernel SHALL restituire `EPERM` al processo chiamante senza interrompere gli altri container in esecuzione nello stesso pod

---

### Requisito 10: Gestione dei Secret con K8s Secrets ed Encryption at Rest

**User Story:** Come responsabile della sicurezza, voglio che tutte le credenziali e i valori sensibili siano gestiti tramite Kubernetes Secrets con cifratura at rest, in modo da eliminare la memorizzazione di testo in chiaro su disco o nei sorgenti.

#### Criteri di Accettazione

1. THE K8s_Secrets SHALL memorizzare le credenziali del database (host, porta, nome database, utente, password di MySQL_Primary e MySQL_Replica), la `APP_KEY` di Laravel, la chiave privata TLS e il certificato TLS; WHEN questi Secret vengono creati, THEN `kubectl get secret <nome> -o yaml` SHALL mostrare i valori come stringhe base64, non in chiaro
2. WHEN la cifratura at rest viene abilitata nel control plane Kubernetes tramite il file `EncryptionConfiguration`, THEN i dati dei K8s_Secrets archiviati in etcd SHALL essere cifrati con il provider configurato (es. `aescbc` o `aesgcm`); questo è verificabile estraendo il valore raw da etcd tramite `etcdctl get` e confermando che il contenuto non è leggibile in chiaro
3. THE Laravel_App SHALL ricevere i valori dei K8s_Secrets come variabili d'ambiente o file montati tramite `envFrom` o `volumeMounts` nel manifest Kubernetes; WHEN il Dockerfile di Laravel_App viene ispezionato tramite `docker inspect`, THEN nessuna credenziale sensibile SHALL essere presente nelle layer dell'immagine o nelle variabili d'ambiente definite nel Dockerfile
4. IF un K8s_Secret viene eliminato tramite `kubectl delete secret` mentre un pod dipendente è in esecuzione, THEN THE Kubernetes SHALL continuare a servire il pod esistente con i valori già montati fino al prossimo riavvio o ricreazione del pod; il pod non SHALL essere terminato automaticamente alla sola eliminazione del Secret
5. WHEN i manifest Kubernetes del progetto vengono analizzati tramite `grep -r` sull'intero repository, THEN nessun file Kubernetes manifest, Dockerfile, o file di configurazione versionato SHALL contenere valori di credenziali sensibili in chiaro (password, chiavi API, certificati privati)
6. IF un pod Laravel_App viene avviato e uno o più K8s_Secrets richiesti come `envFrom` o `volumeMounts` non esistono nel namespace, THEN THE Kubernetes SHALL mantenere il pod in stato `Pending` con il motivo `CreateContainerConfigError` visibile in `kubectl describe pod`, senza avviare il container

---

### Requisito 11: Preservazione delle Funzionalità Applicative dopo la Migrazione

**User Story:** Come Tecnico, come Staff e come Amministratore, voglio che tutte le funzionalità esistenti di TechFix continuino a funzionare correttamente dopo la migrazione, in modo da non subire regressioni nel flusso di lavoro quotidiano.

#### Criteri di Accettazione

1. WHEN un Tecnico autenticato invia una richiesta GET all'endpoint del catalogo prodotti, THEN THE Sistema SHALL restituire HTTP 200 con la lista dei prodotti; WHEN il Tecnico naviga nella pagina di dettaglio di un prodotto, THEN THE Sistema SHALL mostrare la lista dei malfunzionamenti associati e le relative soluzioni di riparazione
2. WHEN un membro dello Staff autenticato invia una richiesta POST/PUT/DELETE agli endpoint di gestione malfunzionamenti, soluzioni o prodotti, THEN THE Sistema SHALL eseguire l'operazione e restituire HTTP 200 o HTTP 302 (redirect after POST) confermando la modifica nel database
3. WHEN un Amministratore autenticato accede all'area di gestione utenti, THEN THE Sistema SHALL permettere la creazione, modifica ed eliminazione di account utente, centri di assistenza e assegnazioni prodotto-staff, confermando ogni operazione con una risposta HTTP 200 o 302
4. WHEN un utente autenticato invia una richiesta di ricerca full-text AJAX verso gli endpoint di ricerca prodotti o malfunzionamenti con un termine di ricerca valido, THEN THE Sistema SHALL restituire una risposta JSON con i risultati pertinenti entro 2 secondi, misurati dal momento dell'invio della richiesta, con un carico di 50 utenti concorrenti che eseguono la stessa ricerca
5. WHEN un membro dello Staff autenticato carica un'immagine per un prodotto tramite il form di upload, THEN THE Sistema SHALL salvare il file nel volume di storage condiviso (`storage/app/public/`) accessibile a tutti i pod Laravel_App, e restituire HTTP 200 o 302; IF il volume di storage non è accessibile in scrittura al momento dell'upload, THEN THE Sistema SHALL restituire HTTP 500 con un messaggio di errore che non espone percorsi di sistema interni
6. WHEN un utente non autenticato invia una richiesta HTTP verso una rotta protetta da autenticazione (area tecnici, staff, amministratore), THEN THE Sistema SHALL rispondere con HTTP 302 con header `Location` che punta alla pagina di login, senza includere nella risposta dati applicativi riservati
7. WHEN un membro dello Staff autenticato tenta di caricare un file non-immagine (es. `.exe`, `.php`, `.sh`) tramite il form di upload prodotto, THEN THE Sistema SHALL rifiutare il file con HTTP 422 o equivalente messaggio di validazione, senza salvare il file nel volume di storage

---

### Requisito 12: Demo di Scalabilità con Scenario Product Recall

**User Story:** Come presentatore del progetto, voglio dimostrare lo scaling automatico in tempo reale durante la demo, in modo da mostrare concretamente il valore dell'HPA in uno scenario realistico.

#### Criteri di Accettazione

1. THE Load_Generator (es. `k6`, `hey`, `wrk` o equivalente) SHALL essere configurato per generare traffico HTTP concorrente di almeno 50 richieste simultanee verso gli endpoint del catalogo prodotti e dei malfunzionamenti del cluster Kubernetes deployato, con una durata minima di 3 minuti
2. WHEN il Load_Generator è attivo e genera il carico configurato, THEN THE Sistema SHALL mostrare un aumento del numero di pod Laravel_App attivi a un valore superiore a `minReplicas` (valore di default: 2), osservabile tramite `kubectl get hpa` o `kubectl get pods` con un intervallo di polling di 15 secondi
3. WHEN il Load_Generator viene fermato e l'utilizzo CPU scende sotto la soglia di scale-down, THEN THE Sistema SHALL mostrare la riduzione del numero di pod Laravel_App al valore `minReplicas` entro 10 minuti, osservabile tramite `kubectl get hpa`
4. WHILE il Load_Generator è attivo e lo scaling verso l'alto è in corso, THE Sistema SHALL mantenere un tasso di successo (HTTP 2xx) di almeno il 95% delle richieste con un tempo di risposta inferiore a 5 secondi, misurato dal Load_Generator nell'output della sessione di test
5. WHILE lo scaling verso l'alto è in corso e almeno un nuovo pod Laravel_App aggiuntivo è in stato `Running`, THEN THE MySQL_Replica SHALL ricevere query di lettura dai nuovi pod, verificabile tramite un incremento del contatore `Com_select` di `SHOW GLOBAL STATUS LIKE 'Com_select'` sul server MySQL_Replica tra l'inizio e la fine della sessione di load test

