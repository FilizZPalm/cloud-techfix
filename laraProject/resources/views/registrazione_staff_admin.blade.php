@extends('layouts.admin_template')

@section('title', 'Registrazione Staff')

@section('cur_page', 'STAFF')



@section('content')

<div class="catalogo-container">
    <h1>Registrazione Staff</h1>

    {{-- Messaggi di errore --}}
    @if(session('error'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per registrare un tecnico --}}
    {{ html()->form('POST', route('crea_staff'))->open() }}
    @csrf

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

    {{-- Cognome --}}
    <div class="stile_tabella">
        {{ html()->label('Cognome', 'cognome')->class('stile_tabella_html_title') }}
        {{ html()->text('cognome')->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('cognome'))
        @foreach ($errors->get('cognome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Password --}}
    <div class="stile_tabella">
        {{ html()->label('Password', 'password')->class('stile_tabella_html_title') }}
        {{ html()->password('password')->class(['stile_tabella_html_text'])->placeholder('Nuova password')->required() }}
    </div>
    @if ($errors->first('password'))
        @foreach ($errors->get('password') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif



    {{-- Pulsante di invio --}}
    <div class="button_container">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma registrazione')->class(['btn-alternativo-noborder']) }}
    </div>

    {{ html()->form()->close() }}
</div>

@endsection