<?php

namespace App\Http\Controllers;

use App\Models\Resources\CentroAssistenza;
use Illuminate\Http\JsonResponse;

class ControllerCentriDiAssistenza extends Controller
{
    public function showCentriDiAssistenza()
    {
        
        $centri_assistenza = CentroAssistenza::paginate();
        return view('centri_assistenza', compact('centri_assistenza'));
    }

    // Metodo per ottenere tutti i centri di assistenza in formato JSON
    public function getAllCentriAssistenza(): JsonResponse
    {
       //recupera e mappa in un array con 'nome' come valore e 'id' come chiave
        $centri = CentroAssistenza::all()->pluck('nome', 'id');

        // Se non ci sono centri di assistenza, restituisce una risposta JSON con un errore
        if ($centri->isEmpty()) {
            return response()->json([
                'success' => false,
                'message' => 'Nessun centro di assistenza trovato', 
            ], 404);  
        }

       
        return response()->json([
            'success' => true,
            'data' => $centri,  
        ], 200);  // Status HTTP 200 per "OK"
    }

}
