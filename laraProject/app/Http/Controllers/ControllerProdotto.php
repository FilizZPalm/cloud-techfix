<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Resources\Prodotto;

class ControllerProdotto extends Controller
{
    public function showProdotti()
    {
        // Passa i prodotti alla vista
        return view('catalogo');
    }

    public function filtraProdotti(Request $request)
    {
        // Ottieni il termine di ricerca dall'input
        $termine = $request->input('termine');
        
        // Controlla se il termine è vuoto
        if (empty($termine)) {
            // Se il termine è vuoto, restituisci l'intera lista con paginazione
            $prodotti = Prodotto::paginate(4);
        } else {
            // Estrai solo la prima parola con [0] e rimuovi gli spazi vuoti con trim
            $termine = explode(' ', trim($termine))[0];
            // Gestione della wildcard '*'
            if (str_ends_with($termine, '*')) {
                // Rimuove tutti i caratteri speciali tranne '*' ^(not)
                $termine = preg_replace('/[^a-zA-Z0-9*]/', '', $termine);
               // match ricerca in desxrizione , against = termine di ricerca, booleanmode =  ricerca parziale , ? ci viene messo termine
                $prodotti = Prodotto::whereRaw("MATCH(descrizione) AGAINST(? IN BOOLEAN MODE)", [$termine])
                ->paginate(4);
            } else {
                // Esegui la ricerca full-text, natural language = termine uguale al termine ? di ricerca
                $prodotti = Prodotto::whereRaw("MATCH(descrizione) AGAINST(? IN NATURAL LANGUAGE MODE)", [$termine])
                ->paginate(4); // Paginazione dei risultati
            }
        }

        // Restituisci la vista parziale aggiornata con la paginazione
        return response()->json([
            //compact = array associativo con prodotti, render = da json a html
            'prodotti' => view('parziale.mostra_prodotti', compact('prodotti'))->render(), 
            //termine serve per creare l'url dinamico
            'paginazione' => view('pagination.paginator', ['paginator' => $prodotti, 'termine' => $termine])->render(),
        ]);

         //mi ritorna le cose in ajax_filtra_prodotti
    }




}
