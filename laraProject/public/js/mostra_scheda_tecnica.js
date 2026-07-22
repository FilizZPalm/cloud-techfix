let catalogoOriginale;
function mostraSchedaTecnica(button) {
    // Accedi ai dati tramite dataset
    // Utilizziamo `dataset` per ottenere i dati passati nel bottone tramite gli attributi data-*
    var id = button.dataset.id; 
    var foto = button.dataset.foto;  // Prende il valore dell'attributo `data-foto` del bottone
    var nome = button.dataset.nome;  
    var descrizione = button.dataset.descrizione;  
    var modalita = button.dataset.modalita; 
    var note = button.dataset.note;  

    //gli stiamo passando id main content in catalogo perche ci copiamo la section del  catalogo
    catalogoOriginale = document.getElementById('main-content').innerHTML;

    // Recupera il template e clona il contenuto
    // Otteniamo il template con `getElementById` e cloniamo il suo contenuto (la struttura HTML del template-scheda-tecnica)
    const template = document.getElementById('template-scheda-tecnica').content.cloneNode(true);

   

    const hiddenIdField = template.querySelector('#prodotto-id');
    hiddenIdField.value = id;


    // Popola i dati dinamici
    // Una volta che il template è clonato, sostituiamo il contenuto dei vari elementi con i dati
    //li cerca nel template
   
    //cerca il template con id prodotto.. e gli assegna il valore = ... del prodotto
    //Il metodo querySelector cerca l'elemento che corrisponde al selettore CSS fornito, in questo caso #prodotto-foto, che rappresenta un elemento con l'ID prodotto-foto.
    template.querySelector('#prodotto-foto').src = foto;  // Impostiamo l'immagine del prodotto con il percorso `foto`
    template.querySelector('#prodotto-foto').alt = nome;  // Impostiamo l'alt text dell'immagine con `nome`
    template.querySelector('#prodotto-nome').textContent = nome;  // Impostiamo il nome del prodotto
    template.querySelector('#prodotto-descrizione').textContent = descrizione;  // Impostiamo la descrizione
    template.querySelector('#prodotto-modalita').textContent = modalita;  // Impostiamo le modalità di installazione
    template.querySelector('#prodotto-note').textContent = note;  // Impostiamo le note tecniche


    // Aggiorna il link al pulsante "Malfunzionamenti"
    const malfunzionamentiButton = template.getElementById('visualizza-malfunzionamenti');
    if (malfunzionamentiButton) {  // Controlla se il bottone esiste (esiste solo se sei autenticato)
        let baseUrl = malfunzionamentiButton.dataset.url;  // Prendi la rotta dal dataset
        malfunzionamentiButton.href = baseUrl.replace('__ID__', id);  // Sostituisci il placeholder con l'ID corretto
    }
    
    // Aggiungi la scheda tecnica al contenuto principale
    // Rimuoviamo il catalogo dal contenuto principale e aggiungiamo la scheda tecnica
    const mainContent = document.getElementById('main-content');  // Otteniamo l'elemento che contiene il catalogo
    mainContent.innerHTML = '';  // Rimuoviamo tutto il contenuto esistente (il catalogo)
    mainContent.appendChild(template);  // Aggiungiamo il template con la scheda tecnica al contenuto principale

    
}
function tornaAlCatalogo() {
    const mainContent = document.getElementById('main-content');
    mainContent.innerHTML = catalogoOriginale;  // Ripristina il contenuto originale del catalogo
}


