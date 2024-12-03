<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Collection;
use App\Models\Resources\Category;
use App\Models\Resources\Product;

class Admin {

    public function getProdsCats(): Collection {
        return Category::where('parId', '!=', 0)->get();
    }

}
