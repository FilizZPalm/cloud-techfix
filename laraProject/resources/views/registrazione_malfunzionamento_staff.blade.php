@extends('layouts.staff_template')

@section('title', 'Registrazione Malfunzionamento')

@section('cur_page', 'CATALOGO')

@section('content')

<section class="catalogo-container">
    <h1>Crea Malfunzionamento</h1>

    {{-- Messaggi di errore --}}
    @if(session('success'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per registrare un malfunzionamento --}}
    {{ html()->form('POST', route('salva_malfunzionamento'))->open() }}
    @csrf

    {{-- Campo nascosto per id_prodotto --}}
    {{ html()->hidden('id_prodotto', $prodotto->id) }}

    {{-- Nome --}}
    <div class="stile_tabella">
        {{ html()->label('Nome', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->text('nome')->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Descrizione --}}
    <div class="stile_tabella">
        {{ html()->label('Descrizione', 'descrizione')->class('stile_tabella_html_title') }}
        {{ html()->text('descrizione')->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('descrizione'))
        @foreach ($errors->get('descrizione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif
       
    {{-- Pulsante di invio --}}
    <div class="button_container">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma registrazione')->class(['btn-alternativo-noborder']) }}
    </div>

</section>
@endsection
