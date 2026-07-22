@extends('layouts.admin_template')

@section('title', 'gestisci_centri_assistenza_admin')

@section('cur_page', 'CENTRI ASSISTENZA')

@section('content')
{{-- Il primo script serve per far funzionare show_hide, senno il browser non lo caricava   --}}
<script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
<script src="{{ asset('js/show_hide.js') }}"></script>



<div class="catalogo-container">
    {{ html()->form()->route('gestisci_form_centro_assistenza')->open() }}
    @csrf
    <h1>Lista Centri Assistenza</h1>
    <br><br>

    <div class="button_container">
        {{ html()->button('<img src="' . asset('img/icona_cestino.svg') . '" class="icon"> Elimina')->id('bottone_elimina')->name('bottone_elimina')->class('btn-alternativo-noborder') ->style('display: none;')  }}
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Modifica')->id('bottone_modifica')->name('bottone_modifica')->class('btn-alternativo-noborder') ->style('display: none;') }}
        <a href="{{ route('registrazione_nuovo_centro_assistenza_admin') }}" class="btn-alternativo-noborder"> <img src="{{ asset('img/plus_icon.svg') }}" class="icon"> Inserisci </a>
    </div>
    <br><br>

    <div class="table-scroll-container">
    @isset($centri)
        @if($centri->isNotEmpty())
        <table class="stile_tabella_checkbox">
            @foreach($centri as $centro)
            <tr>
                <td>{{ html()->checkbox('ids[]', false, $centro->id)->id('centro_' . $centro->id) }}</td>
                <td>{{ $centro->id }}</td>
                <td>{{ $centro->nome }}</td>
                <td>{{ $centro->indirizzo }}</td>
            </tr>
            @endforeach
        </table>
        @else
        <p>Non ci sono centri di assistenza da visualizzare</p>
        @endif
    @endisset()

    {{ html()->form()->close() }}
</div>
</div>
@endsection
