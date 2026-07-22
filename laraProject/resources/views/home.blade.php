@extends(auth()->check() && auth()->user()->role === 'tecnico' ? 'layouts.tecnico_template' : 'layouts.public_template')

@section('title', 'Home')

@section('cur_page','HOME')

@section('content')
<div class="content">
        <!-- Paragrafo introduttivo -->
        <p class="normal_text_corp">Benvenuti nel sito ufficiale di TechFix, leader nell’assistenza tecnica per prodotti tecnologici!</p>
        <p class="normal_text_corp">
            Nel nostro catalogo troverai l’elenco completo dei prodotti con relative schede tecniche. 
            Effettua il login per accedere a informazioni dettagliate su malfunzionamenti e soluzioni tecniche personalizzate.
        </p>
        
        <!-- Immagine -->
        <div class="image">
            <img src="{{ asset('img/image_home.png') }}" alt="Inserire Immagine" class="img_home">
        </div>
        
        <!-- Paragrafo finale -->
        <p class="normal_text_corp">
            Consulta anche l’elenco dei nostri centri di assistenza autorizzati per ricevere supporto vicino a te.
        </p>
    <div class="content">
        <a style="margin-top:100px;" class = "btn-alternativo" href="{{asset('documentazione/documentazione_descrittiva_sito_grp_61.pdf')}}"><img class="icon" src ="{{asset('img/file_icon.svg')}}"> Scarica documentazione</a>
    </div>
</div>
@endsection