<?php

namespace App\Models\Resources;

use Illuminate\Database\Eloquent\Model;
use App\Models\Resources\Prodotto;

class Malfunzionamento extends Model {
    protected $table = 'malfunzionamento';  // Nome della tabella
    protected $primaryKey = 'id';           // La chiave primaria della tabella
    public $timestamps = false;             // Se non stai utilizzando timestamp

    protected $fillable = [
        'nome', 
        'descrizione', 
        'nome_soluzione', 
        'descrizione_soluzione', 
        'id_prodotto'
    ];

    // Relazione inversa con Prodotto
    public function prodotto() {
        return $this->belongsTo(Prodotto::class, 'id_prodotto', 'id'); 
        // 'id_prodotto' è la chiave esterna nella tabella malfunzionamenti
        // 'id' è la chiave primaria della tabella prodotti
    }
}

