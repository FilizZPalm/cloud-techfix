<?php

namespace App\Models\Resources;

use Illuminate\Database\Eloquent\Model;
use App\Models\User;

class Tecnico extends Model {
    // Tabella associata
    protected $table = 'tecnico';

    // Chiave primaria personalizzata
    protected $primaryKey = 'username';
    public $incrementing = false;
    protected $keyType = 'string';

    // Disabilita timestamp automatici
    public $timestamps = false;

    // Campi assegnabili tramite Mass Assignment
    protected $fillable = [
        'username', 
        'dataDiNascita', 
        'specializzazione', 
        'id_centro_assistenza'
    ];


    // Relazione con User
    public function user() {
        return $this->belongsTo(User::class, 'username', 'username');
    }

    // Relazione con CentroAssistenza
    public function centroAssistenza() {
        return $this->belongsTo(CentroAssistenza::class, 'id_centro_assistenza', 'id');
    }
}
