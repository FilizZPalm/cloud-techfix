@extends('layouts.admin_template')

@section('title', 'Registrazione Prodotto')

@section('cur_page', 'CATALOGO')

@section('content')

<section class="catalogo-container">
    <h1>Crea Prodotto</h1>

    {{-- Messaggi di errore --}}
    @if(session('success'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{-- Form per registrare un prodotto --}}
    {{ html()->form('POST', route('crea_prodotto'))->attribute('enctype', 'multipart/form-data')->open() }}
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
       

    {{-- Modalita d'installazione --}}
    <div class="stile_tabella">
        {{ html()->label('Modalita di installazione', 'modalita_installazione')->class('stile_tabella_html_title') }}
        {{ html()->text('modalita_installazione')->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('modalita_istallazione'))
        @foreach ($errors->get('modalita_istallazione') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif
        

    {{-- Note Tecniche --}}
    <div class="stile_tabella">
        {{ html()->label('Note Tecniche', 'note_tecniche')->class('stile_tabella_html_title') }}
        {{ html()->text('note_tecniche')->class(['stile_tabella_html_text'])->required() }}
    </div>
    @if ($errors->first('note_tecniche'))
        @foreach ($errors->get('note_tecniche') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif
        
    <div class="stile_tabella"> {{ html()->label('Immagine del prodotto', 'foto')->class('stile_tabella_html_title') }} 
        {{ html()->file('foto')->class(['stile_tabella_html_text'])->required() }}
    </div> @if ($errors->first('foto'))
     @foreach ($errors->get('foto') as $message) 
    <p class="error_text_form">{{ $message }}</p> 
    @endforeach 
    @endif

    {{-- Categoria --}}
    
    {{-- Pulsante di invio --}}
    <div class="button_container">
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Conferma registrazione')->class(['btn-alternativo-noborder']) }}
    </div>
 
</div>
</section>
@endsection
