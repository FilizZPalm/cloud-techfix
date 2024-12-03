<?php

namespace App\Http\Controllers; 

use Illuminate\View\View;
use App\Models\Admin;
use App\Models\Resources\Product;
use App\Http\Requests\NewProductRequest;
use Illuminate\Http\JsonResponse;

class AdminController extends Controller {

    protected $_adminModel;

    public function __construct() {
        $this->_adminModel = new Admin;
        $this->middleware('can:isAdmin');
    }

    public function index(): View {
        return view('admin');
    }

    public function addProduct(): View {
        $prodCats = $this->_adminModel->getProdsCats()->pluck('name', 'catId');
        return view('product.insert')
                        ->with('cats', $prodCats);
    }

    public function storeProduct(NewProductRequest $request): JsonResponse {

        if ($request->hasFile('image')) {
            $image = $request->file('image');
            $imageName = $image->getClientOriginalName();
        } else {
            $imageName = NULL;
        }

        $product = new Product;
        $product->fill($request->validated());
        $product->image = $imageName;
        $product->save();

        if (!is_null($imageName)) {
            $destinationPath = public_path() . '/images/products';
            $image->move($destinationPath, $imageName);
        };
        
        return response()->json(['redirect' => route('admin')]);
    }

}
