<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Resources\Malfunzionamento;
use App\Models\Resources\Prodotto;

class ControllerMalfunzionamento extends Controller
{

    public function visualizzaMalfunzionamenti($id)
    {
        $prodotto = Prodotto::findOrFail($id);
        return view('visualizza_malfunzionamenti', compact('prodotto'));
    }


    
    public function filtraMalfunzionamenti(Request $request)
    {
        $termine = $request->input('termine');
        $prodottoId = $request->input('prodotto_id'); // Legge l'ID del prodotto

        // Trova il prodotto
        $prodotto = Prodotto::findOrFail($prodottoId);

        // Recupera solo i malfunzionamenti di quel prodotto
        $query = $prodotto->malfunzionamenti();

        if (!empty($termine)) {
            // Estrai solo la prima parola attraverso [0] e rimuovi gli spazi vuoti con trim
            $termine = explode(' ', trim($termine))[0];
            // Esegui la ricerca full-text, natural language = termine uguale al termine ? di ricerca
            $query->whereRaw("MATCH(descrizione) AGAINST(? IN NATURAL LANGUAGE MODE)", [$termine]);
        }
        // Ottiene tutti i malfunzionamenti filtrati
        $malfunzionamenti = $query->get();

        return response()->json([
            'malfunzionamenti' => view('parziale.mostra_malfunzionamenti', compact('malfunzionamenti', 'prodotto'))->render(),
        ]);
    }

    

}
