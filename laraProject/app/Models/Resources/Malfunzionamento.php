<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Malfunzionamento extends Model {
    protected $table = 'malfunzionamento';
    protected $primaryKey = 'id';
    public $timestamps = false;

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
    }
}
