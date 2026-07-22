@extends('layouts.staff_template')

@section('title', 'Modifica Malfunzionamento')

@section('cur_page', 'CATALOGO')

@section('content')

<section class="catalogo-container">
    <h1>Modifica Malfunzionamento</h1>

    {{-- Messaggi di errore --}}
    @if(session('success'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per registrare un malfunzionamento --}}
    {{ html()->form('POST', route('aggiorna_malfunzionamento',['id' => $malfunzionamento->id]))->open() }}
    @csrf



    {{-- Nome --}}
    <div class="stile_tabella">
        {{ html()->label('Nome', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->text('nome', $malfunzionamento->nome)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Descrizione --}}
    <div class="stile_tabella">
        {{ html()->label('Descrizione', 'descrizione')->class('stile_tabella_html_title') }}
        {{ html()->text('descrizione', $malfunzionamento->descrizione)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('descrizione'))
        @foreach ($errors->get('descrizione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif
       
    {{-- Pulsante di invio --}}
    <div class="button_container">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma Modifica')->class(['btn-alternativo-noborder']) }}
    </div>

</section>
@endsection
