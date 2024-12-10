<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Prodotto extends Model {
    // Tabella associata
    protected $table = 'prodotto';

    // Chiave primaria personalizzata (se diversa da "id")
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
