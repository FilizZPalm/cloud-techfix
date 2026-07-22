<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\ControllerProdotto;
use App\Http\Controllers\ControllerCentriDiAssistenza;
use App\Http\Controllers\StaffController;
use App\Http\Controllers\Auth\AuthenticatedSessionController;
use App\Http\Controllers\ControllerMalfunzionamento;
use App\Http\Controllers\ControllerAdmin;



/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "web" middleware group. Make something great!
|
*/

// sezione pubblica
        Route::view('/','home')
                ->name('home');
                
        Route::post('/logout', [AuthenticatedSessionController::class, 'destroy'])
                ->name('logout');

        Route::get('/catalogo', [ControllerProdotto::class, 'showProdotti'])
                ->name('catalogo');

        Route::get('/centri_di_assistenza',[ControllerCentriDiAssistenza::class, 'showCentriDiAssistenza'])
                ->name('centri_di_assistenza');
                
        // Rotta per la ricerca dei prodotti con AJAX
        Route::get('/catalogo/filtra', [ControllerProdotto::class, 'filtraProdotti'])
                ->name('filtra_prodotti');

             
        Route::post('/logout', [AuthenticatedSessionController::class, 'destroy'])
        ->name('logout');
                

        //Tecnico (Malfunzionamenti visualizzazione)-----------------------------

        Route::get('/malfunzionamenti/{id}', [ControllerMalfunzionamento::class, 'visualizzaMalfunzionamenti'])
                ->name('visualizza_malfunzionamenti');

        Route::get('/filtra-malfunzionamenti', [ControllerMalfunzionamento::class, 'filtraMalfunzionamenti'])
                ->name('filtra_malfunzionamenti');





 //admin------------------------------------------------------------------------------------

 //centro di assistenza admin

        Route::get('/gestisci_centri_assistenza_admin', [ControllerAdmin::class, 'showCentriDiAssistenzaAdmin'])
        ->name('gestisci_centri_assistenza_admin')->middleware('can:isAdmin');

        Route::post('/admin/gestisci_form_centro_assistenza', [ControllerAdmin::class, 'gestisciFormCentriAssistenza'])
                ->name('gestisci_form_centro_assistenza')->middleware('can:isAdmin');
                
        Route::get('/modifica_centro_assistenza/{id}', [ControllerAdmin::class, 'apri_modifica_centro_assistenza'])
        ->name('modifica_centro_assistenza')->middleware('can:isAdmin');

        Route::post('/modifica_centro_assistenza/{id}', [ControllerAdmin::class, 'modificaCentroAssistenza'])
        ->name('salva_modifica_centro_assistenza')->middleware('can:isAdmin');

        Route::get('/registrazione_nuovo_centro_assistenza_admin', [ControllerAdmin::class, 'apriRegistrazioneNuovoCentroAssistenza'])
        ->name('registrazione_nuovo_centro_assistenza_admin')->middleware('can:isAdmin');

        Route::post('/crea_centro_assistenza', [ControllerAdmin::class, 'creaCentroAssistenza'])
        ->name('crea_centro_assistenza')->middleware('can:isAdmin');

//tecnici admin

        Route::get('/gestisci_tecnici_admin', [ControllerAdmin::class, 'showTecnici'])
        ->name('gestisci_tecnici_admin')->middleware('can:isAdmin');

        Route::post('/gestisci_form_tecnico', [ControllerAdmin::class, 'gestisciFormTecnici'])
        ->name('gestisci_form_tecnico')->middleware('can:isAdmin');

        Route::get('/modifica_tecnici_admin/{username}', [ControllerAdmin::class, 'modificaTecnico'])
        ->name('modifica_tecnici_admin')->middleware('can:isAdmin');

        Route::post('/modifica_tecnici_admin/{username}', [ControllerAdmin::class, 'salvaModificaTecnico'])
        ->name('salva_modifica_tecnico')->middleware('can:isAdmin');

        Route::get('/registrazione_tecnico_admin', [ControllerAdmin::class, 'apriRegistrazioneNuovoTecnico'])
        ->name('registrazione_tecnico_admin')->middleware('can:isAdmin');

        Route::post('/crea_tecnico', [ControllerAdmin::class, 'creaTecnico'])
        ->name('crea_tecnico')->middleware('can:isAdmin');


//staff admin

        Route::get('/gestisci_staff_admin', [ControllerAdmin::class, 'showStaff'])
        ->name('gestisci_staff_admin')->middleware('can:isAdmin');

        //gestisce bottoni elimina e visualizza
        Route::post('/gestisci_form_staff', [ControllerAdmin::class, 'gestisciFormStaff'])
        ->name('gestisci_form_staff')->middleware('can:isAdmin');

        //gestisce bottoni modifica e gestisci prodotto
        Route::post('/gestisci-form-staff2/{username}', [ControllerAdmin::class, 'gestisciFormStaff2'])
        ->name('gestisci_form_staff2')->middleware('can:isAdmin');

        Route::get('/registrazione_staff_admin', [ControllerAdmin::class, 'apriRegistrazioneNuovoStaff'])
        ->name('registrazione_staff_admin')->middleware('can:isAdmin');

        Route::post('/crea_staff', [ControllerAdmin::class, 'creaStaff'])
        ->name('crea_staff')->middleware('can:isAdmin');

        Route::get('/visualizza_account_staff_admin/{username}', [ControllerAdmin::class, 'visualizzaAccountStaff'])
        ->name('visualizza_account_staff_admin')->middleware('can:isAdmin');

        Route::get('/modifica_staff_admin/{username}', [ControllerAdmin::class, 'modificaStaff'])
        ->name('modifica_staff_admin')->middleware('can:isAdmin');

        Route::post('/modifica_staff_admin/{username}', [ControllerAdmin::class, 'salvaModificaStaff'])
        ->name('salva_modifica_staff')->middleware('can:isAdmin');

        Route::get('/gestione_prodotti_staff_admin/{username}', [ControllerAdmin::class, 'visualizzaProdottiStaff'])
        ->name('gestione_prodotti_staff_admin')->middleware('can:isAdmin');

        Route::post('/rimuovi_prodotto_staff/{username}', [ControllerAdmin::class, 'rimuoviProdottoStaff'])
        ->name('rimuovi_prodotto_staff')->middleware('can:isAdmin');

        Route::get('/assegna_prodotti_staff_admin/{username}', [ControllerAdmin::class, 'assegnaProdottiStaff'])
        ->name('assegna_prodotti_staff_admin')->middleware('can:isAdmin'); 

        Route::post('/assegna_prodotti_staff_admin/{username}', [ControllerAdmin::class, 'salvaProdottiStaff'])
        ->name('salva_prodotti_staff')->middleware('can:isAdmin');


//catalogo admin

        Route::get('/registrazione_prodotto_admin',[ControllerAdmin::class, 'apriRegistrazioneNuovoProdotto'])
        ->name('registrazione_prodotto_admin')->middleware('can:isAdmin');

        Route::post('/crea_prodotto', [ControllerAdmin::class, 'creaProdotti'])
        ->name('crea_prodotto')->middleware('can:isAdmin');

        Route::post('/gestisci_form_prodotto', [ControllerAdmin::class, 'gestisciFormProdotto'])
        ->name('gestisci_form_prodotto')->middleware('can:isAdmin');

        Route::get('/modifica-prodotto/{id}', [ControllerAdmin::class, 'showModificaProdotto'])
        ->name('modifica_prodotto_admin')->middleware('can:isAdmin');

        Route::put('/aggiorna_prodotto/{id}', [ControllerAdmin::class, 'aggiornaProdotto'])
        ->name('aggiorna_prodotto')->middleware('can:isAdmin');



//rotte staff ------------------------------------------------------------------------------
      
        
        Route::get('/catalogo/filtra-staff', [StaffController::class, 'filtraProdottiStaff'])
                ->name('filtra_prodotti_staff');
   
        Route::get('/registrazione_malfunzionamento_staff/{idProdotto}', [StaffController::class, 'creaMalfunzionamento'])
        ->name('registrazione_malfunzionamento_staff')->middleware('can:isStaff');

        Route::post('/salva-malfunzionamento', [StaffController::class, 'salvaMalfunzionamento'])
        ->name('salva_malfunzionamento')->middleware('can:isStaff');

        Route::post('/gestisci_form_malfunzionamento', [StaffController::class, 'gestisciFormMalfunzionamento'])
        ->name('gestisci_form_malfunzionamento')->middleware('can:isStaff');

        Route::get('/modifica_malfunzionamento/{id}', [StaffController::class, 'modificaMalfunzionamento'])
        ->name('modifica_malfunzionamento')->middleware('can:isStaff');

        Route::post('/aggiorna-malfunzionamento/{id}', [StaffController::class, 'aggiornaMalfunzionamento'])
        ->name('aggiorna_malfunzionamento')->middleware('can:isStaff');

       
        Route::post('/gestisci_form_soluzione', [StaffController::class, 'gestisciFormSoluzione'])
        ->name('gestisci_form_soluzione')->middleware('can:isStaff'); 

        Route::get('/modifica-soluzione/{id}', [StaffController::class, 'showModificaSoluzione'])
        ->name('modifica_soluzione_staff')->middleware('can:isStaff');

        Route::post('/salva-modifica-soluzione/{id}', [StaffController::class, 'salvaModificaSoluzione'])
        ->name('salva_modifica_soluzione')->middleware('can:isStaff');


require __DIR__.'/auth.php';

