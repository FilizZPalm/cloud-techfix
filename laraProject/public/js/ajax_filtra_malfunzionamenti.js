// Funzione AJAX per filtrare i malfunzionamenti, si attiva al caricamente della pagina
$(document).ready(function() {
    $('#search-btn').click();  // Simula il click sul bottone 'Cerca'
});


function ajax_filtra_malfunzionamenti(e, url) {
    if (e) e.preventDefault();  // Previene il comportamento predefinito del form (se attivato tramite submit)

    // Ottieni il valore dell'input di ricerca e rimuove eventuali spazi vuoti
    let termine = document.getElementById('cerca_parola').value.trim();
    let prodottoId = document.getElementById('prodotto-id').value; // Legge l'ID prodotto
    url = url + "?termine=" + encodeURIComponent(termine) + "&prodotto_id=" + encodeURIComponent(prodottoId);  // Aggiungi i parametri all'URL
    // Esegui la richiesta AJAX per filtrare i malfunzionamenti
    $.ajax({
        url: url,  // Endpoint che gestisce il filtraggio lato server
        type: 'GET',  // Metodo HTTP usato per la richiesta
        success: function(response) {
            // Aggiorna la tabella con i malfunzionamenti filtrati ricevuti dal server,sostituisce HTML con il response.malf..
            document.getElementById('table-malfunzionamenti').innerHTML = response.malfunzionamenti;
        },
        error: function() {
            alert("Errore durante il recupero dei malfunzionamenti.");
        }
    });
}
