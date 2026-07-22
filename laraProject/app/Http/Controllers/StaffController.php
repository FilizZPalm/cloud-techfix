<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Resources\Prodotto;
use App\Models\Resources\AccessoProdotto;
use App\Models\Resources\Malfunzionamento;
class StaffController extends Controller
{
    public function filtraProdottiStaff(Request $request)
    {
        $usernameStaff = auth()->user()->username;
        
        // Ottieni gli ID dei prodotti accessibili allo staff
        $prodottiIds = AccessoProdotto::where('username_staff', $usernameStaff)->pluck('id_prodotto');
        // Ottieni il termine di ricerca dalla richiesta
        $termine = $request->input('termine');
        
        // Se il termine è vuoto, restituisci tutti i prodotti dello staff con paginazione
        if (empty($termine)) {
            // Paginazione dei prodotti accessibili allo staff
            $prodotti = Prodotto::whereIn('id', $prodottiIds)->paginate(4);
        } else {
            // Estrai solo la prima parola [0] e rimuovi gli spazi vuoti con trim
            $termine = explode(' ', trim($termine))[0];
            // Gestione della wildcard '*' se presente nel termine
            if (str_ends_with($termine, '*')) {
                   // Rimuove tutti i caratteri speciali tranne '*' ^(not)
                $termine = preg_replace('/[^a-zA-Z0-9*]/', '', $termine);
                 //Filtra i prodotti che hanno un id presente nell’array $prodottiIds.
                $prodotti = Prodotto::whereIn('id', $prodottiIds)
                ->where(function($query) use ($termine) {
                    // match ricerca in desxrizione , against = termine di ricerca, booleanmode =  ricerca parziale , ? ci viene messo termine
                    $query->whereRaw("MATCH(descrizione) AGAINST(? IN BOOLEAN MODE)", [$termine]);
                })
                ->paginate(4);

            } else {
                // Cerca i prodotti che corrispondono al termine di ricerca
                $prodotti = Prodotto::whereIn('id', $prodottiIds)
                    ->where(function($query) use ($termine) {
                          // Esegui la ricerca full-text, natural language = termine uguale al termine ? di ricerca
                        $query->whereRaw("MATCH(descrizione) AGAINST(? IN NATURAL LANGUAGE MODE)", [$termine]);
                    })
                    ->paginate(4);
            }
        }

        // Restituisci la vista parziale aggiornata con la paginazione
        return response()->json([
            'prodotti' => view('parziale.mostra_prodotti', compact('prodotti'))->render(),
            'paginazione' => view('pagination.paginator', ['paginator' => $prodotti, 'termine' => $termine])->render(),
        ]);
        //mi ritorna le cose in ajax_filtra_prodotti
    }


    public function creaMalfunzionamento($idProdotto)
    {
        // Verifica che l'utente sia staff
        if (auth()->user()->role !== 'staff') {
            return redirect()->route('catalogo')->with('error', 'Accesso non autorizzato');
        }

        $prodotto = Prodotto::findOrFail($idProdotto);

        return view('registrazione_malfunzionamento_staff', compact('prodotto'));
    }

    public function salvaMalfunzionamento(Request $request)
    {

        // Validazione dell'input
        $request->validate([
            'nome' => 'required|string|max:255',
            'descrizione' => 'required|string',
            'id_prodotto' => 'required|exists:prodotto,id',
        ]);

        // Recupera l'ultimo malfunzionamento creato e calcola il prossimo ID
        $ultimoMalfunzionamento = Malfunzionamento::orderBy('id', 'desc')->first();
        $prossimoId = $ultimoMalfunzionamento ? $ultimoMalfunzionamento->id + 1 : 1;

        
        // Crea il nuovo malfunzionamento
        $malfunzionamento = Malfunzionamento::create([
            'id' => $prossimoId,
            'nome' => $request->nome,
            'descrizione' => $request->descrizione,
            'nome_soluzione' => null,
            'descrizione_soluzione' => null,
            'id_prodotto' => $request->id_prodotto,
        ]);

        $malfunzionamento->save();


        return redirect()->route('catalogo')->with('success', 'Malfunzionamento aggiunto con successo');
    }

    public function gestisciFormMalfunzionamento(Request $request)
{
    
    
    $validated = $request->validate([
        'id' => 'required|integer|exists:malfunzionamento,id',
    ]);

    // Ottieni l'ID del malfunzionamento dal form
    $malfunzionamentoId = $validated['id'];
    
    if ($request->has('bottone_elimina')) {
        
        return $this->eliminaMalfunzionamento($malfunzionamentoId);
    }

    elseif ($request->has('bottone_modifica')) {
        
        return redirect()->route('modifica_malfunzionamento', ['id' => $malfunzionamentoId]);
    }
}

public function eliminaMalfunzionamento($id)
{
    // Trova il malfunzionamento da eliminare in base all'ID
    $malfunzionamento = Malfunzionamento::find($id);
    
    if (!$malfunzionamento) {
        return redirect()->route('catalogo')->with('error', 'Malfunzionamento non trovato.');
    }
    $malfunzionamento->delete();

    
    return redirect()->route('catalogo')->with('success', 'Malfunzionamento eliminato con successo.');
}

public function modificaMalfunzionamento($id)
{
    $malfunzionamento = Malfunzionamento::findOrFail($id);

    // Mostra la vista di modifica con i dati del malfunzionamento
    return view('modifica_malfunzionamento_staff', compact('malfunzionamento'));
}

public function aggiornaMalfunzionamento(Request $request, $id)
{
    // Valida i dati ricevuti
    $validatedData = $request->validate([
        'nome' => 'required|string|max:255',
        'descrizione' => 'required|string',
    ]);

    
    $malfunzionamento = Malfunzionamento::findOrFail($id);

    // Aggiorna solo i campi modificabili
    $malfunzionamento->nome = $validatedData['nome'];
    $malfunzionamento->descrizione = $validatedData['descrizione'];
    $malfunzionamento->save();

    
    return redirect()->route('catalogo')->with('success', 'Malfunzionamento aggiornato con successo.');
}



public function gestisciFormSoluzione(Request $request)
{
   

    $validated = $request->validate([
        'id' => 'required|integer', 
    ]);

    $malfunzionamentoId = $validated['id'];
   

    
    $malfunzionamento = Malfunzionamento::findOrFail($malfunzionamentoId);

    
    
    if ($request->has('bottone_elimina')) {
        // Svuota i campi soluzione
        $malfunzionamento->nome_soluzione = null;
        $malfunzionamento->descrizione_soluzione = null;
        $malfunzionamento->save(); 
        return redirect()->route('catalogo')->with('success', 'Soluzione eliminata con successo');
    }

   
    if ($request->has('bottone_modifica')) {
        return redirect()->route('modifica_soluzione_staff', ['id' => $malfunzionamentoId]);
    }

    return back()->withErrors(['error' => 'Azione non valida.']);
}


 public function showModificaSoluzione($id)
 {
    $malfunzionamento = Malfunzionamento::findOrFail($id);
     return view('modifica_soluzione_staff', compact('malfunzionamento'));
 }
 
 public function salvaModificaSoluzione(Request $request, $id)
 {
     $validated = $request->validate([
         'nome_soluzione' => 'required|string|max:255',
         'descrizione_soluzione' => 'required|string',
     ]);
 
     $malfunzionamento = Malfunzionamento::findOrFail($id);
 
     // Aggiorna i campi della soluzione
     $malfunzionamento->nome_soluzione = $validated['nome_soluzione'];
     $malfunzionamento->descrizione_soluzione = $validated['descrizione_soluzione'];
     $malfunzionamento->save();
 
     return redirect()->route('catalogo')->with('success', 'Soluzione aggiornata con successo');
 }


}  
        