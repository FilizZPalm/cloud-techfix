<?php

namespace App\Http\Controllers; 

use App\Models\Resources\CentroAssistenza;
use Illuminate\Http\Request;
use App\Models\Admin;
use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\DB;
use App\Models\User;
use App\Models\Resources\Tecnico;
use App\Models\Resources\Staff;
use App\Models\Resources\Prodotto;
use App\Models\Resources\Malfunzionamento;


class ControllerAdmin extends Controller {

    protected $_adminModel;

    public function __construct() {
        $this->_adminModel = new Admin;
        $this->middleware('can:isAdmin');
    }

    //GESTIONE CENTRI DI ASSISTENZA-----------------------------------------------------------------------


    public function showCentriDiAssistenzaAdmin(Request $request): View
    {
        // Prendiamo "termine" dalla query string per eventuali ricerche o filtri
        $termine = $request->input('termine');  
        
        // Recuperariamo Centri Assistenza
        $centri = $this->_adminModel->getCentriAssistenza();
        
        // Ritorna la vista passando i dati dei centri e il termine di ricerca
        return view('gestisci_centri_assistenza_admin', compact('centri', 'termine'));
    }

    public function gestisciFormCentriAssistenza(Request $request)
    {
        // 'ids' presente e array
        $validated = $request->validate(['ids' => 'required|array']);
        
        // Recupera gli ID dal form
        $centriSelezionati =  $validated['ids'];

        if ($request->has('bottone_elimina')) {
            $this->eliminaCentriAssistenza($centriSelezionati);
            return redirect()->route('gestisci_centri_assistenza_admin')
                            ->with('success', 'Centri di assistenza eliminati con successo.');
        
        } elseif ($request->has('bottone_modifica')) {
            // Reindirizza alla pagina di modifica del primo centro selezionato
            return redirect()->route('modifica_centro_assistenza', ['id' => $centriSelezionati[0]]);
        }

        return redirect()->back();
    }

    public function eliminaCentriAssistenza(array $centriSelezionati)
    {
        if (!empty($centriSelezionati)) {
            // Trova i tecnici associati ai centri selezionati
            $tecnici = Tecnico::whereIn('id_centro_assistenza', $centriSelezionati)->get();

            // Elimina manualmente gli utenti associati ai tecnici
            foreach ($tecnici as $tecnico) {
                User::where('username', $tecnico->username)->delete();
            }

            // Ora elimina i centri di assistenza (questo eliminerà i tecnici grazie a ON DELETE CASCADE)
            CentroAssistenza::whereIn('id', $centriSelezionati)->delete();
        }
    }




    
    public function apri_modifica_centro_assistenza(int $id): View
    {
        // Trova il centro di assistenza tramite ID, genera un errore 404 se non esiste
        $centro = CentroAssistenza::findOrFail($id); 
        
        
        return view('modifica_centro_assistenza_admin')->with('centro', $centro);
    }

    public function modificaCentroAssistenza(Request $request, $id): RedirectResponse
    {
        // Validazione dei dati in ingresso
        $validated = $request->validate([
            'nome' => 'required|string|max:255',
            'indirizzo' => 'required|string|max:255',
        ]);

        // Trova il centro tramite ID
        $centro = CentroAssistenza::findOrFail($id);
        
        // Aggiorna i dati del centro con quelli validati dal form
        $centro->nome = $validated['nome'];
        $centro->indirizzo = $validated['indirizzo'];
        $centro->save(); 


        return redirect()->route('gestisci_centri_assistenza_admin')
                        ->with('success', 'Centro aggiornato con successo.');
    }

    public function apriRegistrazioneNuovoCentroAssistenza(): View 
    {
        return view('registrazione_nuovo_centro_assistenza_admin');
    }

    public function creaCentroAssistenza(Request $request)
    {
        // Validazione dei dati in ingresso
        $request->validate([
            'nome' => 'required|string|max:255',
            'indirizzo' => 'required|string|max:255',
        ]);

        // Trova il primo ID mancante per assegnarlo al nuovo centro
        $idsEsistenti = CentroAssistenza::pluck('id')->toArray(); // Ottiene tutti gli ID esistenti
        sort($idsEsistenti); // Ordina  in ordine crescente
        $nuovoId = 1; // Inizializza il nuovo ID a 1

        // Trova il primo ID disponibile
        foreach ($idsEsistenti as $id) {
            if ($id == $nuovoId) {
                $nuovoId++; // Se l'ID esiste già, passa al successivo
            } else {
                break; // Se trova un ID libero, esce dal ciclo
            }
        }

        // Crea il nuovo centro di assistenza con l'ID disponibile
        CentroAssistenza::create([
            'id' => $nuovoId,
            'nome' => $request->input('nome'),
            'indirizzo' => $request->input('indirizzo')
        ]);

      
        return redirect()->route('gestisci_centri_assistenza_admin')
                        ->with('success', 'Centro di Assistenza creato con successo!');
    }

    //GESTIONE TECNICI-----------------------------------------------------------------------

    public function showTecnici(): View 
    {
        // Recupera tutti i tecnici
        $tecnici = $this->_adminModel->getTecnici();
        
       
        return view('gestisci_tecnici_admin', compact('tecnici'));
    }

    public function gestisciFormTecnici(Request $request)
    {
        // Valida che il campo 'ids' sia presente e sia un array
        $validated = $request->validate([
            'ids' => 'required|array',
        ]);

        // Recupera gli ID dei tecnici selezionati dal form
        $tecniciSelezionati = $validated['ids'];

        
        if ($request->has('bottone_elimina')) {
            $this->eliminaTecnici($tecniciSelezionati);

            return redirect()->route('gestisci_tecnici_admin')
                            ->with('success', 'Tecnici eliminati con successo.');
        
        
        } elseif ($request->has('bottone_modifica')) {
            return redirect()->route('modifica_tecnici_admin', ['username' => $tecniciSelezionati[0]]);
        }

        
        return redirect()->back();
    }

    public function eliminaTecnici(array $tecniciSelezionati)
    {
        // Controlla che ci siano tecnici selezionati 
        if (!empty($tecniciSelezionati)) {
            User::whereIn('username', $tecniciSelezionati)->delete();
        }
    }

    public function modificaTecnico($username)
    {
        // Trova il tecnico nel database tramite username
        $tecnico = Tecnico::where('username', $username)->firstOrFail();
        
        $user = $tecnico->user;

        // Definisce le specializzazioni disponibili per il dropdown
        $specializzazioni = [
            'Tecnico Certificato IOS' => 'Tecnico Certificato IOS',
            'Tecnico hardware' => 'Tecnico hardware',
        ];

        // Recupera l'elenco dei centri di assistenza per il menu a tendina
       
       // Recupera l'elenco dei centri di assistenza come un array 
        $centriDiAssistenza = CentroAssistenza::pluck('nome', 'id')->toArray();

        //verifica se esiste un centro di assistenza associato a un tecnico e se tale centro di assistenza è presente nell'array
        if ($tecnico->id_centro_assistenza && isset($centriDiAssistenza[$tecnico->id_centro_assistenza])) {
        // Memorizza il centro di assistenza associato al tecnico 
        $centroTecnico = [$tecnico->id_centro_assistenza => $centriDiAssistenza[$tecnico->id_centro_assistenza]];

        // Rimuove il centro dalla posizione originale
        unset($centriDiAssistenza[$tecnico->id_centro_assistenza]);

        // Unisce l'array mettendo il centro del tecnico in prima posizione
        $centriDiAssistenza = $centroTecnico + $centriDiAssistenza;
    }

        return view('modifica_tecnici_admin', compact('tecnico', 'user', 'specializzazioni', 'centriDiAssistenza'));
    }

    public function salvaModificaTecnico(Request $request, $username)
    {
        // Trova il tecnico nel database e il suo utente associato
        $tecnico = Tecnico::where('username', $username)->firstOrFail();
        $user = $tecnico->user;

        // Validazione dei dati in ingresso
        $request->validate([
            'username' => 'required|string|max:255|unique:user,username,' . $user->username . ',username',
            'nome' => 'required|string|max:255',
            'cognome' => 'required|string|max:255',
            'dataDiNascita' => 'required|date',
            'specializzazione' => 'required|in:Tecnico Certificato IOS,Tecnico hardware',
            'centroDiAssistenza' => 'required|exists:centro_assistenza,id',
        ]);

        // Aggiorna i dati dell'utente
        $user->update([
            'username' => $request->username,
            'nome' => $request->nome,
            'cognome' => $request->cognome,
            //Verifica se il campo password è stato compilato, se si cripta la password, altrimenti mantiene la password attuale
            'password' => $request->filled('password') ? bcrypt($request->password) : $user->password, // Se la password è vuota, non la cambia
        ]);

        // Aggiorna i dati del tecnico
        $tecnico->update([
            'username' => $request->username,
            'dataDiNascita' => $request->dataDiNascita,
            'specializzazione' => $request->specializzazione,
            'id_centro_assistenza' => $request->centroDiAssistenza, 
        ]);

       
        return redirect()->route('gestisci_tecnici_admin')->with('success', 'Tecnico modificato con successo!');
    }

    public function apriRegistrazioneNuovoTecnico(ControllerCentriDiAssistenza $controllerCentriAssistenza): View
    {
        // Recupera tutti i centri di assistenza disponibili
        $response = $controllerCentriAssistenza->getAllCentriAssistenza(); //risponde in JSON
        $centroDiAssistenza = $response->getData()->data ?? []; //se data non esiste, restituisce un array vuoto

        // Mostra la vista per registrare un nuovo tecnico con i centri disponibili
        return view('registrazione_tecnico_admin', compact('centroDiAssistenza'));
    }

    public function creaTecnico(Request $request)
    {
        // Recupera l'ultimo tecnico creato per generare un username progressivo
        $ultimoTecnico = Tecnico::orderBy('username', 'desc')->first();
        if ($ultimoTecnico) {
            // Estrae la parte alfabetica e numerica dallo username
            preg_match('/(\D+)(\d+)/', $ultimoTecnico->username, $matches);//	\D+ cattura la parte alfabetica , \d+ cattura la parte numerica
            $letter = $matches[1] ?? 'tecnico'; // Parte letterale dello username
            $number = intval($matches[2] ?? '0'); // Numero progressivo
            $prossimoUsername = $letter . ($number + 1);  // compone la parte alfabetica seguita dal numero progressivo incrementato di 1 
        } else {
            // Se non ci sono tecnici, inizia da "tecnico1"
            $prossimoUsername = 'tecnico1';
        }

        // Controlla che lo username generato sia univoco, incrementando il numero se necessario
        while (User::where('username', $prossimoUsername)->exists()) {
            $number++;
            $prossimoUsername = $letter . $number;
        }

        // Validazione dei dati del tecnico
        $request->validate([
            'nome' => 'required|string|max:255',
            'cognome' => 'required|string|max:255',
            'password' => 'required|string|min:1', 
            'dataDiNascita' => 'required|date',
            'specializzazione' => 'required|in:Tecnico Certificato IOS,Tecnico hardware',
            'centroDiAssistenza' => 'required|exists:centro_assistenza,id',
        ]);

        // Crea un nuovo utente con ruolo "tecnico"
        $user = User::create([
            'username' => (string)$prossimoUsername, // Converte lo username in stringa
            'nome' => $request->input('nome'),
            'cognome' => $request->input('cognome'),
            'password' => bcrypt($request->input('password')),
            'role' => 'tecnico',
        ]);

        // Crea il record del tecnico nella tabella "tecnico"
        Tecnico::create([
            'username' => $user->username,
            'dataDiNascita' => $request->input('dataDiNascita'),
            'specializzazione' => $request->input('specializzazione'),
            'id_centro_assistenza' => $request->input('centroDiAssistenza'),
        ]);

        return redirect()->route('gestisci_tecnici_admin')->with('success', 'Tecnico creato con successo!');
    }



    //GESTIONE STAFF -----------------------------------------------------------------------

    public function showStaff(): View 
    {
        // Recupera tutti i membri dello staff 
        $staff = $this->_adminModel->getStaff();
        
        return view('gestisci_staff_admin', compact('staff'));
    }

    public function gestisciFormStaff(Request $request)
    {
        // Validazione dei dati inviati dalla richiesta
        $validated = $request->validate([
            'ids' => 'required|array', 
        ]);

        // Ottieni gli staff selezionati tramite i loro id
        $staffSelezionati = $validated['ids'];

        
        if ($request->has('bottone_elimina')) {
            $this->eliminaStaff($staffSelezionati);
            return redirect()->route('gestisci_staff_admin')  ->with('success', 'Staff eliminato con successo.');

        } elseif ($request->has('bottone_visualizza_account')) {
            
            return redirect()->route('visualizza_account_staff_admin', ['username' => $staffSelezionati[0]]);

        } 

        // In caso di errore o nessuna azione, torna alla pagina precedente
        return redirect()->back();
    }

    public function eliminaStaff(array $staffSelezionati)
    {
        // Verifica se sono stati selezionati degli staff
        if (!empty($staffSelezionati)) {
            User::whereIn('username', $staffSelezionati)->delete();
        }
    }

    public function apriRegistrazioneNuovoStaff(): View {
        return view('registrazione_staff_admin');
    }

    public function creaStaff(Request $request)
    {
        // Recupera l'ultimo staff creato e calcola un nuovo username
        $ultimoStaff = User::where('role', 'staff')->orderBy('username', 'desc')->first();
        if ($ultimoStaff) {
            preg_match('/(\D+)(\d+)/', $ultimoStaff->username, $matches);  // \D+ cattura la parte alfabetica , \d+ cattura la parte numerica
            $letter = $matches[1] ?? 'staff'; // parte alfabetica
            $number = intval($matches[2] ?? '0'); // parte numerica
            $prossimoUsername = $letter . ($number + 1); // compone la parte alfabetica seguita dal numero progressivo incrementato di 1 
        } else {
            $prossimoUsername = 'staff1';
        }

        // Verifica che l'username non sia già esistente, incrementa il numero se necessario
        while (User::where('username', $prossimoUsername)->exists()) {
            $number++;
            $prossimoUsername = $letter . $number;
        }

        // Validazione dei dati inviati nella richiesta
        $request->validate([
            'nome' => 'required|string|max:255',
            'cognome' => 'required|string|max:255',
            'password' => 'required|string|min:1',  
        ]);

        // Crea un nuovo utente con il ruolo di staff
        $user = User::create([
            'username' => (string)$prossimoUsername,
            'nome' => $request->input('nome'),
            'cognome' => $request->input('cognome'),
            'password' => bcrypt($request->input('password')),
            'role' => 'staff',
        ]);

        // Crea un record nella tabella staff
        Staff::create([
            'username' => $user->username,
        ]);

        // Redirect con un messaggio di successo
        return redirect()->route('gestisci_staff_admin')->with('success', 'Staff creato con successo!');
    }

    public function visualizzaAccountStaff($username) {
        // Recupera i dati dello staff specificato
        $staff = User::where('username', $username)->where('role', 'staff')->first();
        if (!$staff) {
            // Se lo staff non esiste, ritorna un errore
            return redirect()->back()->with('error', 'Staff non trovato.');
        }

        // Recupera i prodotti associati allo staff
        $prodotti = DB::table('accesso_prodotto')
                    ->join('prodotto', 'accesso_prodotto.id_prodotto', '=', 'prodotto.id')
                    ->where('accesso_prodotto.username_staff', $username)
                    ->select('prodotto.*')
                    ->get();

        // Ritorna la vista per visualizzare l'account dello staff
        return view('visualizza_account_staff_admin', compact('staff', 'prodotti'));
    }

    public function gestisciFormStaff2(Request $request, $username)
    {
        
        if ($request->has('bottone_modifica')) {
            return redirect()->route('modifica_staff_admin', ['username' => $username]);

        } elseif ($request->has('bottone_gestisci_prodotto')) {
            return redirect()->route('gestione_prodotti_staff_admin', ['username' => $username]);
        }
        return redirect()->back();
    }

    public function modificaStaff($username)
    {
        // Recupera i dati dello staff e dell'utente associato
        $staff = Staff::where('username', $username)->firstOrFail();
        $user = User::where('username', '=', $username)->firstOrFail();

        
        return view('modifica_staff_admin', compact('staff', 'user'));
    }

    public function salvaModificaStaff(Request $request, $username)
    {
        // Trova lo staff e l'utente da modificare
        $staff = Staff::where('username', $username)->firstOrFail();
        $user = User::where('username', '=', $username)->first();

        // Validazione dei dati inviati
        $request->validate([
            'username' => 'required|string|max:255|unique:user,username,' . $user->username . ',username',
            'nome' => 'required|string|max:255',
            'cognome' => 'required|string|max:255',
            'password' => 'nullable|string|min:1', 
        ]);

        // Modifica i dati dell'utente
        $user->update([
            'username' => $request->username,
            'nome' => $request->nome,
            'cognome' => $request->cognome,
            'password' => $request->filled('password') ? bcrypt($request->password) : $user->password, // Se la password è vuota, non cambia
        ]);

        // Modifica i dati dello staff
        $staff->update([
            'username' => $request->username,
        ]);

       
        return redirect()->route('gestisci_staff_admin')->with('success', 'Staff modificato con successo!');
    }

    public function visualizzaProdottiStaff($username)
    {
        // Verifica se lo staff esiste
        $staff = User::where('username', $username)->where('role', 'staff')->first();
        if (!$staff) {
            return redirect()->back()->with('error', 'Staff non trovato.');
        }

        // Recupera i prodotti associati allo staff
        $prodotti = DB::table('accesso_prodotto')
                    ->join('prodotto', 'accesso_prodotto.id_prodotto', '=', 'prodotto.id')
                    ->where('accesso_prodotto.username_staff', $username)
                    ->select('prodotto.*')
                    ->get();

        return view('gestione_prodotti_staff_admin', compact('staff', 'prodotti'));
    }

    public function rimuoviProdottoStaff(Request $request, $username)
    {
        // Validazione dei prodotti selezionati
        $validated = $request->validate([
            'ids' => 'required|array',
        ]);

        // Recupera i prodotti selezionati per rimuoverli dallo staff
        $prodottiSelezionati = $validated['ids'];

        if ($request->has('bottone_rimuovi_prodotto')) {
            DB::table('accesso_prodotto')
                ->where('username_staff', $username)
                ->whereIn('id_prodotto', $prodottiSelezionati)
                ->delete();

            return redirect()->route('gestione_prodotti_staff_admin', ['username' => $username])
                            ->with('success', 'Prodotto rimosso correttamente.');
        }

        return redirect()->back();
    }

    public function assegnaProdottiStaff($username)
    {
        // Verifica se lo staff esiste
        $staff = User::where('username', $username)->where('role', 'staff')->first();
        if (!$staff) {
            return redirect()->back()->with('error', 'Staff non trovato.');
        }

        // Recupera i prodotti disponibili non assegnati
        $prodottiDisponibili = DB::table('prodotto')
                                ->leftJoin('accesso_prodotto', 'prodotto.id', '=', 'accesso_prodotto.id_prodotto')
                                ->whereNull('accesso_prodotto.id_prodotto')
                                ->select('prodotto.*')
                                ->get();

    
        return view('assegna_prodotti_staff_admin', compact('staff', 'prodottiDisponibili'));
    }

    public function salvaProdottiStaff(Request $request, $username)
    {
        // Validazione dei prodotti selezionati per l'assegnazione
        $validated = $request->validate([
            'ids' => 'required|array',
        ]);

        // Assegna i prodotti selezionati allo staff
        foreach ($validated['ids'] as $prodotto_id) {
            DB::table('accesso_prodotto')->insert([
                'username_staff' => $username,
                'id_prodotto' => $prodotto_id,
            ]);
        }

        return redirect()->route('gestione_prodotti_staff_admin', ['username' => $username])
                        ->with('success', 'Prodotto/i assegnato/i con successo.');

    }



    //GESTIONE PRODOTTO -----------------------------------------------------------------------



    public function apriRegistrazioneNuovoProdotto(): View {
        return view('registrazione_prodotto_admin');
    }
    
    public function creaProdotti(Request $request)
    {
        // Recupera l'ultimo prodotto creato per calcolare il prossimo ID
        $ultimoProdotto = Prodotto::orderBy('id', 'desc')->first();
        $prossimoId = $ultimoProdotto ? $ultimoProdotto->id + 1 : 1;
    
        // Validazione dei dati inviati dal form
        $request->validate([
            'nome' => 'required|string|max:255',
            'descrizione' => 'required|string|max:255',
            'modalita_installazione' => 'required|string|max:255',
            'note_tecniche' => 'required|string|max:255',
            'foto' => 'required|image|mimes:jpeg,png,jpg,gif|max:5120',  // La foto è obbligatoria
        ]);
    
       
        if ($request->hasFile('foto')) {
            // Crea un nome unico per l'immagine basato sul timestamp
            //time vede i secondi dal 1 gennaio 1970, extension aggiunge l'estenzione del file
            $imageName = time() . '.' . $request->file('foto')->extension();
            // Sposta l'immagine nella cartella "img/prodotti"
            $request->file('foto')->move(public_path('img/prodotti'), $imageName);
    
            // Crea il nuovo prodotto con i dati inviati dal form
            $prodotto = new Prodotto([
                'id' => $prossimoId,
                'nome' => $request->nome,
                'descrizione' => $request->descrizione,
                'modalita_installazione' => $request->modalita_installazione,
                'note_tecniche' => $request->note_tecniche,
                'foto' => $imageName
            ]);
    
            $prodotto->save();

            return redirect()->route('catalogo')->with('success', 'Prodotto creato con successo!');
        } else {
            return back()->withErrors(['foto' => 'Errore caricamento immagine.']);
        }
    }
    
    public function gestisciFormProdotto(Request $request)
    {
        // Valida l'ID del prodotto selezionato
        $validated = $request->validate([
            'id' => 'required|integer',
        ]);
    
        // Recupera l'ID del prodotto selezionato
        $prodottoSelezionato = $validated['id'];
    
        
        if ($request->has('bottone_elimina')) {
            return $this->eliminaProdotto($prodottoSelezionato);

        } elseif ($request->has('bottone_modifica')) {
            return redirect()->route('modifica_prodotto_admin', ['id' => $prodottoSelezionato]);
        }
    }
    
    public function eliminaProdotto($id)
    {
        try {
            $prodotto = Prodotto::find($id);

            //se esiste
            if ($prodotto) {
                $prodotto->delete();
                return redirect()->route('catalogo')->with('success', 'Prodotto eliminato con successo.');
            } else {
                return redirect()->route('catalogo')->with('error', 'Prodotto non trovato.');
            }
        } catch (\Exception $e) {
            // Se c'è un errore durante l'eliminazione, restituisce un messaggio di errore
            return redirect()->route('catalogo')->with('error', 'Si è verificato un errore durante l\'eliminazione del prodotto.');
        }
    }
    
    public function showModificaProdotto($id)
    {
        $prodotto = Prodotto::find($id);
    
        if ($prodotto) {
            // Se il prodotto esiste, mostra la vista di modifica
            return view('modifica_prodotto_admin', compact('prodotto'));
        } else {
            return redirect()->route('catalogo')->with('error', 'Prodotto non trovato.');
        }
    }
    
    public function aggiornaProdotto(Request $request, $id)
    {
        // Valida i dati inviati per aggiornare il prodotto
        $validated = $request->validate([
            'nome' => 'required|string|max:255',
            'descrizione' => 'required|string|max:255',
            'modalita_installazione' => 'required|string|max:255',
            'note_tecniche' => 'required|string|max:255',
            'foto' => 'nullable|image|mimes:jpeg,png,jpg,gif|max:5120',  // La foto è opzionale
        ]);
    
        try {
            $prodotto = Prodotto::find($id);
    
            if ($prodotto) {
                // Aggiorna i dati del prodotto
                $prodotto->nome = $validated['nome'];
                $prodotto->descrizione = $validated['descrizione'];
                $prodotto->modalita_installazione = $validated['modalita_installazione'];
                $prodotto->note_tecniche = $validated['note_tecniche'];
    
                // Se è stata caricata una nuova immagine, aggiorna la foto
                if ($request->hasFile('foto')) {
                    // Genera un nome univoco per l'immagine, utilizzando il timestamp attuale e l'estensione del file
                    //time vede i secondi dal 1 gennaio 1970, extension aggiunge l'estenzione del file
                    $imageName = time() . '.' . $request->file('foto')->extension();
                    $request->file('foto')->move(public_path('img/prodotti'), $imageName);
                    $prodotto->foto = $imageName;
                }
    
                $prodotto->save();
    
                return redirect()->route('catalogo')->with('success', 'Prodotto aggiornato con successo.');
            } else {
                return redirect()->route('catalogo')->with('error', 'Prodotto non trovato.');
            }
        } catch (\Exception $e) {
            return redirect()->route('catalogo')->with('error', 'Si è verificato un errore durante l\'aggiornamento del prodotto.');
        }
    }

   
    
}