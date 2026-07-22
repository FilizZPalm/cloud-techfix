@extends(
    auth()->check() && auth()->user()->role === 'tecnico' ? 'layouts.tecnico_template' :
    (auth()->check() && auth()->user()->role === 'admin' ? 'layouts.admin_template' :
    (auth()->check() && auth()->user()->role === 'staff' ? 'layouts.staff_template' : 'layouts.public_template'))
)
@section('title', 'Catalogo')

@section('cur_page', 'CATALOGO')

@section('content')
<div class="catalogo-container" id="main-content">
    <h1>Catalogo Prodotti</h1>

    <!-- Includi jQuery -->
    <script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
    <script src="{{ asset('js/ajax_pagination.js') }}"></script>
    <!-- Includi il file JavaScript, appena si carica la funzione in ajax_filtra_prodotti si attiva -->
    <script src="{{ asset('js/ajax_filtra_prodotti.js') }}"></script>

    @auth
        @if(auth()->user()->role === 'admin')
            <!-- Contenuto per l'admin -->
            <div class="button_container">
                <a href="{{ route('registrazione_prodotto_admin') }}" class="btn-alternativo-noborder"> <img src="{{ asset('img/plus_icon.svg') }}" class="icon"> Inserisci Prodotto </a>
    </div>
    <br><br>
        @endif
    @endauth

    <!-- Barra di Ricerca -->

    <div class="search-bar">
        
        {{ html()->text('parola')->id('cerca_parola')->placeholder('Cerca un prodotto...')->class('input') }}
        @auth
            @if(auth()->user()->role === 'staff')
                {{ html()->button('Cerca')->class('btn')->id('search-btn')->attribute('onclick', 'ajax_filtra_prodotti(event, "' . route('filtra_prodotti_staff') . '")') }}
            @else
                {{ html()->button('Cerca')->class('btn')->id('search-btn')->attribute('onclick', 'ajax_filtra_prodotti(event, "' . route('filtra_prodotti') . '")') }}
            @endif
        @endauth
 <!--crea bottone cerca,+ crea dinamicamente l'URL -->
        @guest
             {{-- lato client viene eseguita ajax_filtra_prodotti, lato server si attiva la rotta filtra_prodotto --}}
            {{ html()->button('Cerca')->class('btn')->id('search-btn')->attribute('onclick', 'ajax_filtra_prodotti(event, "' . route('filtra_prodotti') . '")') }}
        @endguest
    </div>


    <!-- Includi il file JavaScript -->
    <script src="{{ asset('js/mostra_scheda_tecnica.js') }}"></script>
    <!-- Includi il Template -->
    @include('parziale.scheda_tecnica')
    
    
    <!-- Elenco prodotti -->
    <div id="products-list"> <!-- mostra_prodotti.balde.php -->
   
      
    </div>


    <!-- Paginazione -->
    <div id="pagination">
        
    </div>

</div>
@endsection
