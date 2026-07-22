<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Models\Resources\CentroAssistenza;


class Admin extends Model
{

    public function getCentriAssistenza()
    {
        $centri = CentroAssistenza::paginate();
        return $centri;
    }

    public function getTecnici()
    {
        $tecnici = User::where('role', 'tecnico')->get();
        return $tecnici;
    }

    public function getStaff()
    {
        $staff = User::where('role', 'staff')->get();
        return $staff;
    }
}