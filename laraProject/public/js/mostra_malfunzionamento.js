let catalogoMalfunzionamento;
function mostraMalfunzionamento(button) {
    // Accedi ai dati tramite dataset
    var id = button.dataset.id;
    var nomeMalfunzionamento = button.dataset.nome;
    var descrizioneMalfunzionamento = button.dataset.descrizione;
    var nomeSoluzione = button.dataset.nome_soluzione;
    var descrizioneSoluzione = button.dataset.descrizione_soluzione;
    var nomeProdotto = button.dataset.nome_prodotto;
    
    //trova l'elemento con id main-content e prende l'html 
    catalogoMalfunzionamento = document.getElementById('main-content').innerHTML;

    // Recupera il template e clona il contenuto
    const template = document.getElementById('template-scheda-tecnica').content.cloneNode(true);

    const hiddenIdField = template.querySelector('#malfunzionamento-id');
    if(hiddenIdField)  // Controlla se il campo esiste
    {
        hiddenIdField.value = id;
    }

     // Aggiungi il valore al secondo campo nascosto 
     const hiddenIdField2 = template.querySelector('#malfunzionamento-id-2');
     if(hiddenIdField2)  // Controlla se il campo esiste
     {
     hiddenIdField2.value = id;  // Impostiamo lo stesso valore
     }

   //cerca il template con id malf.. e gli assegna il valore del nome e descrizione del malfunzionamento
   //Il metodo querySelector cerca l'elemento che corrisponde al selettore CSS fornito, in questo caso #malfunzionamento-nome, che rappresenta un elemento con l'ID malfunzionamento-nome
    template.querySelector('#malfunzionamento-nome').textContent = nomeMalfunzionamento;
    template.querySelector('#malfunzionamento-descrizione').textContent = descrizioneMalfunzionamento;

    // Controlla se la soluzione è disponibile
    if (nomeSoluzione && descrizioneSoluzione) {
        template.querySelector('#soluzione-nome').textContent = nomeSoluzione;
        template.querySelector('#soluzione-descrizione').textContent = descrizioneSoluzione;
    } else {
        template.querySelector('#soluzione-nome').textContent = "Soluzione non ancora disponibile";
        template.querySelector('#soluzione-descrizione').textContent = "La soluzione per questo malfunzionamento non è ancora stata trovata.";
    }
    template.querySelector('#prodotto-nome').textContent = nomeProdotto;
    
    // Aggiungi la scheda tecnica al contenuto principale
    const catalogoContainer = document.getElementById('main-content');  // Ottieni il contenitore del catalogo
    catalogoContainer.innerHTML = '';  // Rimuovi il contenuto esistente in main-content
    catalogoContainer.appendChild(template);  // Aggiungi il template con la scheda tecnica
}

// Funzione per tornare alla lista di malfunzionamenti
function tornaAiMalfunzionamenti() {
    const catalogoContainer = document.getElementById('main-content');
    catalogoContainer.innerHTML = catalogoMalfunzionamento;  // Ripristina il contenuto originale del catalogo
}

