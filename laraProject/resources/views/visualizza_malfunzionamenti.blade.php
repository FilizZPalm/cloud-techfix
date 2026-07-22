@extends(
    auth()->check() && auth()->user()->role === 'tecnico' ? 'layouts.tecnico_template' :
    (auth()->check() && auth()->user()->role === 'admin' ? 'layouts.admin_template' :
    (auth()->check() && auth()->user()->role === 'staff' ? 'layouts.staff_template' : abort(403)))
)


@section('title', 'Malfunzionamenti')

@section('cur_page','CATALOGO')

@section('content')
<script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
<script src="{{ asset('js/mostra_malfunzionamento.js') }}"></script>  <!-- Aggiungi il file JS -->
<script src="{{ asset('js/ajax_filtra_malfunzionamenti.js') }}"></script>
<div id = "main-content" class="catalogo-container">
    <h1>Malfunzionamenti</h1>

    <input type="hidden" id="prodotto-id" value="{{ $prodotto->id }}">

    <!-- Barra di Ricerca -->
    <div class="search-bar">

        {{ html()->text('parola')->id('cerca_parola')->placeholder('Cerca un prodotto...')->class('input') }}
        {{ html()->hidden('prodotto_id', $prodotto->id)->id('prodotto-id') }}  <!-- Aggiunto ID prodotto -->

        {{-- lato client viene eseguita ajax_filtra_malfunzionamenti, lato server si attiva la rotta filtra_malfunzionamenti --}}
        {{ html()->button('Cerca')->class('btn')->id('search-btn')->attribute('onclick', 'ajax_filtra_malfunzionamenti(event, "' . route('filtra_malfunzionamenti') . '")') }}
    
    </div>
    @auth
    @if(auth()->user()->role === 'staff')
    <div class="button_container_scheda_tecnica">
            <!-- Link per inserire un nuovo malfunzionamento -->
            <a href="{{ route('registrazione_malfunzionamento_staff', ['idProdotto' => $prodotto->id]) }}" class="btn-alternativo-noborder">
    <img src="{{ asset('img/plus_icon.svg') }}" class="icon"> Aggiungi Malfunzionamento
            </a>
        </div>
    @endif
    @endauth
        
        <!-- Contenitore scrollabile -->
        <div id = "table-malfunzionamenti" class="table-scroll-container">
            
        </div>

    <a href="{{ route('catalogo') }}" class="btn-alternativo-noborder"><img  src="{{ asset('img/go_back_arrow.svg') }}" class="icon">Indietro</a>
    

</div>


<!-- Template che viene copiata da js mostra_malfunzionamento e viene visualizzata alla fine della funzione -->


<template id="template-scheda-tecnica">
    <div class="scheda-tecnica-container">
        <h1 class="scheda-tecnica-title">Dettagli Malfunzionamento</h1>

    @auth
    @if(auth()->user()->role === 'staff')
        <!-- Sezione gestione malfunzionamento per lo staff -->
        <div class="button_container_scheda_tecnica">
        <form method="POST" action="{{ route('gestisci_form_malfunzionamento') }}">
                @csrf

                  <!-- Campo nascosto per l'ID del malfunzionamento -->
                  <input type="hidden" id="malfunzionamento-id" name="id">

                <!-- Bottone Elimina -->
                <button type="submit" name="bottone_elimina" class="btn-alternativo-noborder">
                    <img src="{{ asset('img/icona_cestino.svg') }}" class="icon"> Elimina
                </button>

                <!-- Bottone Modifica -->
                <button type="submit" name="bottone_modifica" class="btn-alternativo-noborder">
                    <img src="{{ asset('img/pencil_icon.svg') }}" class="icon"> Modifica
                </button>
            </form>
            
        </div>
    @endif
@endauth


       

        <!-- Dettagli prodotto -->
        <div class="scheda-tecnica-header">
            <h3>Prodotto:</h3>
            <p id="prodotto-nome"></p> <!-- Ora viene direttamente dalla variabile $prodotto -->
        </div>

        <!-- Dettagli malfunzionamento -->
        <div class="scheda-tecnica-info">
            <h3 id="malfunzionamento-nome"></h3>
            <p id="malfunzionamento-descrizione"></p>
        </div>

        <br></br>
        <h1 class="scheda-tecnica-title">Dettagli Soluzione</h1>

        @auth
    @if(auth()->user()->role === 'staff')
        <!-- Sezione gestione soluzione per lo staff -->
        <div class="button_container_scheda_tecnica">
        <form method="POST" action="{{ route('gestisci_form_soluzione') }}">
    @csrf
    <input type="hidden" id="malfunzionamento-id-2" name="id">

    <!-- Bottone Elimina -->
    <button type="submit" name="bottone_elimina" class="btn-alternativo-noborder">
        <img src="{{ asset('img/icona_cestino.svg') }}" class="icon"> Elimina
    </button>

    <!-- Bottone Modifica -->
    <button type="submit" name="bottone_modifica" class="btn-alternativo-noborder">
        <img src="{{ asset('img/pencil_icon.svg') }}" class="icon"> Modifica/Aggiungi
    </button>
</form>
            
        </div>
    @endif
@endauth

        <!-- Dettagli soluzione -->
        <div class="scheda-tecnica-info">
            <h3 id="soluzione-nome"></h3>
            <p id="soluzione-descrizione"></p>
        </div>

        <!-- Bottone per tornare al catalogo -->
    
        <button class="btn-alternativo-noborder" onclick="tornaAiMalfunzionamenti()">
            <img src="{{ asset('img/go_back_arrow.svg') }}" class="icon" alt="Indietro">
            Indietro
        </button>

        

    </div>
</template>

@endsection