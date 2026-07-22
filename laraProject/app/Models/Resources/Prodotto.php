<?php

namespace App\Models\Resources;

use Illuminate\Database\Eloquent\Model;
use App\Models\Resources\Malfunzionamento; 

class Prodotto extends Model {
    // Tabella associata
    protected $table = 'prodotto';
  
    protected $primaryKey = 'id';

    // Nessun timestamp automatico
    public $timestamps = false;

    // Campi assegnabili
    protected $fillable = [
        'nome', 
        'descrizione', 
        'note_tecniche', 
        'modalita_installazione', 
        'foto'
    ];

    // Relazione con Malfunzionamento
    public function malfunzionamenti() {
        return $this->hasMany(Malfunzionamento::class, 'id_prodotto', 'id');
    }
    
}