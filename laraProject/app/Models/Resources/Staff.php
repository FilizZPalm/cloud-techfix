<?php

namespace App\Models\Resources;

use Illuminate\Database\Eloquent\Model;
use App\Models\User;

class Staff extends Model {
    protected $table = 'staff';
    protected $primaryKey = 'username';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'username'
    ];

    // Relazione con Utente
    public function user() {
        return $this->belongsTo(User::class, 'username', 'username');
    }  

}
