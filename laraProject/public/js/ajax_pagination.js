// Intercetta i clic sui link di paginazione nel catalogo
$(document).on('click', '#pagination a', function(e) {
    e.preventDefault(); // Evita il normale comportamento di navigazione, si assicura che funzioni tramite ajax

    //this = link che è stato cliccato .attr('href') = prende l'attributo href del link cliccato
    let url = $(this).attr('href');
    
    // Ottieni il termine di ricerca
    let parola = document.getElementById('cerca_parola').value.trim();

    //verifica se l’URL contiene già il parametro termine. Se non è presente (-1 significa che non è stato trovato) allora
    if (url.indexOf('termine=') === -1) {
        //aggiunge il parametro termine all’URL. Se l’URL contiene già un punto di domanda (?), aggiunge & per concatenare i parametri. Altrimenti, aggiunge il ? per la prima concatenazione.
        url += (url.includes('?') ? '&' : '?') + 'termine=' + parola;
    }

    // Chiama la funzione per caricare i prodotti con il nuovo URL
    caricaProdotti(url);
});



// Funzione per caricare i prodotti con AJAX
function caricaProdotti(url) {

    $.ajax({
        url: url, // URL della pagina successiva
        type: 'GET', // Metodo HTTP

        success: function(response) {

            // Aggiorna la lista dei prodotti
            $('#products-list').html(response.prodotti); //prodotti successivi restituiti  dal controller

            // Aggiorna i controlli di paginazione
            $('#pagination').html(response.paginazione);
           
        },

        error: function() {
            alert('Errore durante il caricamento della pagina.');
        }
    });
}
