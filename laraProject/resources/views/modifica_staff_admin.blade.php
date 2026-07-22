@extends('layouts.admin_template')

@section('title', 'Visualizza staff admin')

@section('cur_page', 'STAFF')

@section('content')

<div class="catalogo-container">

<h1>Modifica Tecnico</h1>

    {{-- Messaggi di errore --}}
    @if(session('error'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per modificare lo staff --}}
    {{ html()->form('POST', route('salva_modifica_staff', $staff->username))->open() }}
    @csrf


    <div class="stile_tabella">
        {{ html()->label('Username', 'username')->class('stile_tabella_html_title') }}
        {{ html()->text('username', $user->username, ['id' => 'username'])->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('username'))
        @foreach ($errors->get('username') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif


    <div class="stile_tabella">
        {{ html()->label('Nome', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->text('nome', $user->nome, ['id' => 'nome'])->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif


    <div class="stile_tabella">
        {{ html()->label('Cognome', 'cognome')->class('stile_tabella_html_title') }}
        {{ html()->text('cognome', $user->cognome, ['id' => 'cognome'])->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('cognome'))
        @foreach ($errors->get('cognome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif


    <div class="stile_tabella">
        {{ html()->label('Password', 'password')->class('stile_tabella_html_title') }}
        {{ html()->password('password')->class(['stile_tabella_html_text'])->placeholder('Nuova password (lascia vuoto per mantenere la password attuale)') }}
    </div>
    @if ($errors->first('password'))
        @foreach ($errors->get('password') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif


    
    
    <div class="button_container">
    {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma modifiche')->class(['btn-alternativo-noborder']) }}
    </div>

    {{ html()->form()->close() }}
</div>
</section>
@endsection