@extends('layouts.admin_template')

@section('title', 'Modifica Prodotto')

@section('cur_page', 'CATALOGO')

@section('content')

<section class="catalogo-container">
    <h1>Modifica Prodotto</h1>

    {{-- Messaggi di errore --}}
    @if(session('success'))
        <p class="error_text_form">{{ session('success') }}</p>
    @endif

    {{-- Form per modificare il prodotto --}}
    {{ html()->form('POST', route('aggiorna_prodotto', ['id' => $prodotto->id]))->attribute('enctype', 'multipart/form-data')->open() }}
    @csrf
    @method('PUT')

    {{-- Nome --}}
    <div class="stile_tabella">
        {{ html()->label('Nome', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->text('nome', $prodotto->nome)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Descrizione --}}
    <div class="stile_tabella">
        {{ html()->label('Descrizione', 'descrizione')->class('stile_tabella_html_title') }}
        {{ html()->text('descrizione', $prodotto->descrizione)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('descrizione'))
        @foreach ($errors->get('descrizione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Modalita di installazione --}}
    <div class="stile_tabella">
        {{ html()->label('Modalita di installazione', 'modalita_installazione')->class('stile_tabella_html_title') }}
        {{ html()->text('modalita_installazione', $prodotto->modalita_installazione)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('modalita_installazione'))
        @foreach ($errors->get('modalita_installazione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Note Tecniche --}}
    <div class="stile_tabella">
        {{ html()->label('Note Tecniche', 'note_tecniche')->class('stile_tabella_html_title') }}
        {{ html()->text('note_tecniche', $prodotto->note_tecniche)->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('note_tecniche'))
        @foreach ($errors->get('note_tecniche') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Immagine del prodotto --}}
    <div class="stile_tabella">
        {{ html()->label('Immagine del prodotto da inserire', 'foto')->class('stile_tabella_html_title') }}
        {{ html()->file('foto')->class(['stile_tabella_html_text']) }}
        {{-- Mostra l immagine corrente --}}
        <div class="stile_tabella">
        {{ html()->label('Immagine del prodotto esistente', 'foto')->class('stile_tabella_html_title') }}
            <img src="{{ asset('img/prodotti/' . $prodotto->foto) }}" alt="Immagine del prodotto" style="max-width: 300px;">
        </div>
    </div>


    @if ($errors->first('foto'))
        @foreach ($errors->get('foto') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Pulsante di invio --}}
    <div class="button_container">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma Modifica')->class(['btn-alternativo-noborder']) }}
    </div>

    {{ html()->form()->close() }}
</section>
@endsection
