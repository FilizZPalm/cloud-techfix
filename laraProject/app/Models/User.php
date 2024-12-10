<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class User extends Model {
    protected $table = 'user';
    protected $primaryKey = 'username';
    public $incrementing = false;  // Poiché `username` non è un integer
    protected $keyType = 'string';

    protected $fillable = [
        'username', 
        'password', 
        'nome', 
        'cognome', 
        'role'
    ];

    // Definisci una relazione con Tecnico
    public function tecnico() {
        return $this->hasOne(Tecnico::class, 'username', 'username');
    }
    public function staff() {
        return $this->hasOne(Staff::class, 'username', 'username');
    }
}
