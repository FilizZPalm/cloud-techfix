// Funzione AJAX per filtrare i prodotti, si attiva al caricamento della pagina
$(document).ready(function() {
    $('#search-btn').click();  // Simula il click sul bottone 'Cerca'
});

function ajax_filtra_prodotti(e, url) {
    if (e) e.preventDefault();  // Evita il comportamento predefinito, cioè il submit del form, quindi verra gestita da ajax

    // Ottieni il valore dell'input di ricerca, trim toglie spazi vuoti
    let parola = document.getElementById('cerca_parola').value.trim();

    // Determina l'URL corretto per il filtro
    url = url + "?termine=" + encodeURIComponent(parola);  // Aggiungi il parametro 'termine' all'URL, encode formatta termine per l'url
    
    // Esegui la chiamata AJAX
    $.ajax({
        url: url,  // Se staff, chiama la rotta per i prodotti dello staff
        type: 'GET',
        success: function(response) {
            //qui ci va il risultato dei filtraprodotti, cioe la vista parziale mostra_prodotti, che riempie la products-list in catalogo
            document.getElementById('products-list').innerHTML = response.prodotti; 
            document.getElementById('pagination').innerHTML = response.paginazione;
            //mi fa vedere le cose nel catalogo
        },
        error: function() {
            alert("Errore durante la ricerca.");
        }
    });
}