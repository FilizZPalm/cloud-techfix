$(function () {
    var eliminaBtn = $('#bottone_elimina');
    var modificaBtn = $('#bottone_modifica');
    var visualizzaAccountBtn = $('#bottone_visualizza_account');
    var rimuoviProdottoBtn = $('#bottone_rimuovi_prodotto');

    // Funzione per verificare lo stato delle checkbox
    function checkCheckboxes() {
        var numSelezionati = $('input[name="ids[]"]:checked').length;

        // Mostra i bottoni "Elimina" e "Rimuovi Prodotto" se almeno una checkbox è selezionata
        if (numSelezionati > 0) {
            eliminaBtn.prop('disabled', false).css('display', 'inline-block');
            rimuoviProdottoBtn.prop('disabled', false).css('display', 'inline-block');
        } else {
            eliminaBtn.prop('disabled', true).css('display', 'none');
            rimuoviProdottoBtn.prop('disabled', true).css('display', 'none');
        }

        // Mostra i bottoni "Modifica" e "Visualizza Account" se una sola checkbox è selezionata
        if (numSelezionati === 1) {
            modificaBtn.prop('disabled', false).css('display', 'inline-block');
            visualizzaAccountBtn.prop('disabled', false).css('display', 'inline-block');
        } else {
            modificaBtn.prop('disabled', true).css('display', 'none');
            visualizzaAccountBtn.prop('disabled', true).css('display', 'none');
        }
    }

    // Richiama la funzione al caricamento della pagina per impostare correttamente lo stato dei bottoni
    checkCheckboxes();

    // Aggiungi un listener per l'evento "change" su tutte le checkbox, per richiamare la funzione checkCheckboxes
    $('input[name="ids[]"]').change(checkCheckboxes);
});
