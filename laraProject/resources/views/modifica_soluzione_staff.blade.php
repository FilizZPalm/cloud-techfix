@extends('layouts.staff_template')

@section('title', 'Modifica Soluzione')

@section('cur_page', 'CATALOGO')

@section('content')

<section class="catalogo-container">
    <h1>Modifica Soluzione</h1>

    {{-- Messaggi di errore --}}
    @if(session('success'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per registrare una soluzione --}}
    {{ html()->form('POST', route('salva_modifica_soluzione',['id' => $malfunzionamento->id]))->open() }}
    @csrf



    {{-- Nome --}}
    <div class="stile_tabella">
        {{ html()->label('Nome soluzione', 'nome_soluzione')->class('stile_tabella_html_title') }}
        {{ html()->text('nome_soluzione', $malfunzionamento->nome_soluzione)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Descrizione --}}
    <div class="stile_tabella">
        {{ html()->label('Descrizione Soluzione', 'descrizione_soluzione')->class('stile_tabella_html_title') }}
        {{ html()->text('descrizione_soluzione', $malfunzionamento->descrizione_soluzione)->class(['stile_tabella_html_text'])->required() }}
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
