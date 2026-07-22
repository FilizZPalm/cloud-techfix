@extends('layouts.admin_template')

@section('title', 'Creazione Centro di Assistenza')

@section('cur_page', 'CENTRI ASSISTENZA')

@php
    use App\Models\CentroAssistenza;
@endphp

@section('content')
<section class="catalogo-container">
   
    <h1>Crea Centro di Assistenza</h1>

    @if(session('error'))
        <p class="error_text_form">{{ session('error') }}</p>
    @endif

    {{ html()->form()->route('crea_centro_assistenza')->open() }}
    @csrf

    <div class="section_account_paziente">
        {{ html()->label('Nome del Centro', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->text('nome')->class(['stile_tabella_html_text'])->required() }}
    </div>

    @if ($errors->first('nome'))
        @foreach ($errors->get('nome') as $message)
            <p class="error_text_form">{{ $message }}</p>
        @endforeach
    @endif

    <div class="section_account_paziente">
        {{ html()->label('Indirizzo', 'indirizzo')->class('stile_tabella_html_title') }}
        {{ html()->text('indirizzo')->class(['stile_tabella_html_text'])->required() }}
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