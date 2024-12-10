<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\Pivot;

class AccessoProdotto extends Pivot {
    // Tabella associata
    protected $table = 'accesso_prodotto';

    // Chiavi primarie composte
    protected $primaryKey = ['id_prodotto', 'username_staff'];

    // Disabilita auto-incremento delle chiavi
    public $incrementing = false;

    // Disabilita i timestamp automatici
    public $timestamps = false;

    // Campi assegnabili tramite Mass Assignment
    protected $fillable = [
        'id_prodotto', 
        'username_staff'
    ];

    /**
     * Relazione con il modello `Prodotto`
     */
    public function prodotto() {
        return $this->belongsTo(Prodotto::class, 'id_prodotto', 'id');
    }

    /**
     * Relazione con il modello `Staff`
     */
    public function staff() {
        return $this->belongsTo(Staff::class, 'username_staff', 'username');
    }
}
