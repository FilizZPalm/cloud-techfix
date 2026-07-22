@extends('layouts.admin_template')

@section('title', 'Modifica Tecnico')

@section('cur_page', 'TECNICI')

@php
    use App\Models\User;
@endphp

@section('content')



<script>
    

    // Funzione per calcolare la data di oggi e la data di 100 anni fa
    document.addEventListener('DOMContentLoaded', function() {
        // Calcola la data di oggi e la data di 100 anni fa
        const today = new Date().toISOString().split('T')[0];
        const hundredYearsAgo = new Date();
        hundredYearsAgo.setFullYear(hundredYearsAgo.getFullYear() - 100);
        const hundredYearsAgoString = hundredYearsAgo.toISOString().split('T')[0];

        // Imposta i limiti di data per il campo "dataDiNascita"
        const dateInput = document.querySelector('input[name="dataDiNascita"]');
        if (dateInput) {
            dateInput.setAttribute('max', today);
            dateInput.setAttribute('min', hundredYearsAgoString);
        }
    });
</script>
<section class="catalogo-container">


    <h1>Modifica Tecnico</h1>

    {{-- Messaggi di errore --}}
    @if(session('error'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per modificare il tecnico --}}
    {{ html()->form('POST', route('salva_modifica_tecnico', $tecnico->username))->open() }}
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


    
    <div class="stile_tabella">
        {{ html()->label('Data di Nascita', 'dataDiNascita')->class('stile_tabella_html_title') }}
        {{ html()->date('dataDiNascita', $tecnico->dataDiNascita)->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('dataDiNascita'))
        @foreach ($errors->get('dataDiNascita') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    
    <div class="stile_tabella">
        {{ html()->label('Specializzazione', 'specializzazione')->class('stile_tabella_html_title') }}
        {{ html()->select('specializzazione', $specializzazioni, $tecnico->specializzazione)->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('specializzazione'))
        @foreach ($errors->get('specializzazione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

   
    <div class="stile_tabella">
    {{ html()->label('Centro di Assistenza', 'centroDiAssistenza')->class('stile_tabella_html_title') }}
    {{ html()->select('centroDiAssistenza', $centriDiAssistenza, $tecnico->id_centro_assistenza)->class(['stile_tabella_html_text'])->required() }}
</div>
    @if ($errors->first('centroDiAssistenza'))
        @foreach ($errors->get('centroDiAssistenza') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    <div class="button_container">
    {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma modifiche')->class(['btn-alternativo-noborder']) }}
    </div>

    {{ html()->form()->close() }}
</section>
@endsection