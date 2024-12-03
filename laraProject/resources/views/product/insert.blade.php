@extends('layouts.admin')

@section('title', 'Area Admin')

@section('scripts')

@parent
<script src="{{ asset('js/functions.js') }}" ></script>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.5.1/jquery.min.js"></script>

<script>
$(function () {
    var actionUrl = "{{ route('newproduct.store') }}";
    var formId = 'addproduct';
    $(":input").on('blur', function (event) {
        if(event.relatedTarget.type=="submit"){return;}
        var formElementId = $(this).attr('id');
        doElemValidation(formElementId, actionUrl, formId);
    });
    $("#addproduct").on('submit', function (event) {
        event.preventDefault();
        doFormValidation(actionUrl, formId);
    });
});
</script>

@endsection

@section('content')
<div class="static">
    <h3>Aggiungi Prodotti</h3>
    <p>Utilizza questa form per inserire un nuovo prodotto nel Catalogo</p>

    <div class="container-contact">
        <div class="wrap-contact">
            {{ html()->form()->route('newproduct.store')->class(['contact-form'])->id('addproduct')->acceptsFiles()->open() }}
            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Nome Prodotto', 'name')->class(['label-input']) }}
                {{ html()->text('name')->class(['input'])->id('name') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Categoria', 'catId')->class(['label-input']) }}
                {{ html()->select('catId', $cats)->class(['input'])->id('catId') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Immagine','image')->class(['label-input']) }}
                {{ html()->input('file','image')->class(['input'])->id('image') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Descrizione Breve','descShort')->class(['label-input']) }}
                {{ html()->text('descShort')->class(['input'])->id('descShort') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Prezzo','price')->class(['label-input']) }}
                {{ html()->text('price')->class(['input'])->id('price') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Sconto (%)','discountPerc')->class(['label-input']) }}
                {{ html()->text('discountPerc')->class(['input'])->id('discountPerc') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('In Sconto','discounted')->class(['label-input']) }}
                {{ html()->select('discounted', ['1' => 'Si', '0' => 'No'], 1)->class(['input'])->id('discounted') }}
            </div>

            <div  class="wrap-input  rs1-wrap-input">
                {{ html()->label('Descrizione Estesa','descLong')->class(['label-input']) }}
                {{ html()->textarea('descLong', '')->class(['input'])->id('descLong')->rows(2) }}
            </div>

            <div class="container-form-btn">
                {{ html()->submit('Aggiungi Prodotto')->class(['form-btn1']) }}
            </div>
                        
            {{ html()->form()->close() }}   
        </div>
    </div>

</div>
@endsection


