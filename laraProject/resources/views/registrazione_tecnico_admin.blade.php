@extends('layouts.admin_template')

@section('title', 'Registrazione Tecnico')

@section('cur_page', 'TECNICI')

@section('content')

<script>
    

    // Funzione per calcolare la data di oggi e la data di 100 anni fa
    document.addEventListener('DOMContentLoaded', function() {
        // Calcola la data di oggi e la converte in una stringa ISO (yyyy-mm-dd) e la separa dal tempo (T)
        const today = new Date().toISOString().split('T')[0];
        // Crea un oggetto Date per la data di 100 anni fa (basato sulla data odierna)
        const hundredYearsAgo = new Date();
        hundredYearsAgo.setFullYear(hundredYearsAgo.getFullYear() - 100);
        // Converte la data di 100 anni fa in una stringa ISO (yyyy-mm-dd) e la separa dal tempo (T)
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
    <h1>Registrazione Tecnico</h1>

    {{-- Messaggi di errore --}}
    @if(session('error'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per registrare un tecnico --}}
    {{ html()->form('POST', route('crea_tecnico'))->open() }}
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

    {{-- Data di Nascita --}}
    <div class="stile_tabella">
        {{ html()->label('Data di Nascita', 'dataDiNascita')->class('stile_tabella_html_title') }}
        {{ html()->date('dataDiNascita')->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('dataDiNascita'))
        @foreach ($errors->get('dataDiNascita') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    <div class="stile_tabella"> {{ html()->label('Specializzazione', 'specializzazione')->class('stile_tabella_html_title') }} {{ html()->select('specializzazione', [ 'Tecnico Certificato IOS' => 'Tecnico Certificato IOS', 'Tecnico hardware' => 'Tecnico hardware' ], null)->class(['stile_tabella_html_text'])->required() }} </div>
    @if ($errors->first('specializzazione'))
        @foreach ($errors->get('specializzazione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    {{-- Centro di Assistenza --}}
<div class="stile_tabella">
    @if (!empty($centroDiAssistenza))
        {{ html()->label('Centro di Assistenza', 'centroDiAssistenza')->class('stile_tabella_html_title') }}
        {{ html()->select('centroDiAssistenza', $centroDiAssistenza, null)
            ->class(['stile_tabella_html_text'])->required() }}
    @else
        <p class="error_text_form">Non ci sono centri di assistenza disponibili. Aggiungine uno prima di creare un tecnico.</p>
    @endif
</div>

    {{-- Pulsante di invio --}}
    <div class="stile_tabella">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma registrazione')->class(['btn-alternativo-noborder']) }}
    </div>

    {{ html()->form()->close() }}
</section>

@endsection