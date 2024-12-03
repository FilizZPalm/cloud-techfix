<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Pagination\LengthAwarePaginator;
use App\Models\Resources\Category;
use App\Models\Resources\Product;

class Catalog extends Model {

    public function getTopCats(): Collection {
        return Category::where('parId', 0)->get();
    }

    public function getCatsByParId(array $topId): Collection {
        return Category::whereIn('parId', $topId)->get();
    }

    // Estrae i prodotti della categoria/e $catId (tutti o solo quelli in sconto), eventualmente ordinati
    public function getProdsByCat(array $catId, int $paged = 1, string $order = null,
                                  bool $discounted = false): LengthAwarePaginator {

        $prods = Product::whereIn('catId', $catId)
                ->orWhereHas('prodCat', function ($query) use ($catId) {
                        $query->whereIn('parId', $catId);
        });
        if ($discounted) {
            $prods = $prods->where('discounted', true);
        }
        if (!is_null($order)) {
            $prods = $prods->orderBy('discountPerc', $order);
        }
        return $prods->paginate($paged);
    }

}
