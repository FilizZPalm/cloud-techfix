<?php

namespace App\Models\Resources;

use Illuminate\Database\Eloquent\Model;
use App\Models\Resources\Tecnico;

class CentroAssistenza extends Model {
    // Tabella associata
    protected $table = 'centro_assistenza';

    // Chiave primaria
    protected $primaryKey = 'id';

    // Disabilita timestamp automatici
    public $timestamps = false;

    // Campi assegnabili tramite Mass Assignment
    protected $fillable = [
        'nome', 
        'indirizzo'
    ];


    // Relazione con Tecnico
    public function tecnici() {
        return $this->hasMany(Tecnico::class, 'id_centro_assistenza', 'id');
    }
}

