@extends('layouts.admin_template')

@section('title', 'modifica_centro_assistenza_admin')

@section('cur_page', 'CENTRI ASSISTENZA')


@section('content')
<section class="catalogo-container">
       
    
    <h1>Modifica Centro Assistenza</h1>

    {{-- Messaggi di errore --}}
    @if(session('error'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form di modifica --}}
    {{ html()->form('POST', route('salva_modifica_centro_assistenza', $centro->id))->open() }}
    @csrf

    <div class="stile_tabella">
        {{ html()->label('Nome', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->text('nome', $centro->nome)->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    <div class="stile_tabella">
        {{ html()->label('Indirizzo', 'indirizzo')->class('stile_tabella_html_title') }}
        {{ html()->text('indirizzo', $centro->indirizzo)->class('stile_tabella_html_text')->required() }}
    </div>
    @if ($errors->first('indirizzo'))
        @foreach ($errors->get('indirizzo') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    <div class="button_container">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma modifiche')->class(['btn-alternativo-noborder']) }}
    </div>
    {{ html()->form()->close() }}
</section>
@endsection
        
        