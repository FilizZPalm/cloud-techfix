<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use App\Models\Resources\Staff;
use App\Models\Resources\Tecnico;


class User extends Authenticatable {

    protected $table = 'user';
    protected $primaryKey = 'username';
    public $incrementing = false;  // Poiché `username` non è un integer
    protected $keyType = 'string';

    // Define the role property
    protected $role;

    // Campi Assegnabili (Mass Assignment)
    protected $fillable = [
        'username', 
        'password', 
        'nome', 
        'cognome', 
        'role'
    ];

    // Campi Nascosti
    protected $hidden = [
        'username',
        'password',        // Nasconde la password
        'remember_token',  // Nasconde il token di autenticazione
    ];

    // Definisci una relazione con Tecnico
    public function tecnico() {
        return $this->hasOne(Tecnico::class, 'username', 'username');
    }
    public function staff() {
        return $this->hasOne(Staff::class, 'username', 'username');
    }
    
    public function hasRole($role): bool {
        // Assicura che $role sia trattato come un array (nel caso in cui sia passato un singolo valore)
        $role = (array) $role;
    
        // Verifica se il ruolo dell'utente ($this->role) è presente nell'array $role
        return in_array($this->role, $role);
    }
    
}
