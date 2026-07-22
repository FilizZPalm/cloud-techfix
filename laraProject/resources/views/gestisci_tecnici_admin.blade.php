@extends('layouts.admin_template')

@section('title', 'Gestisci tecnici admin')

@section('cur_page', 'TECNICI')

@section('content')
<script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
<script src="{{ asset('js/show_hide.js') }}"></script>


<div class="catalogo-container">
    {{ html()->form()->route('gestisci_form_tecnico')->open() }}
    @csrf
    <h1>Lista Tecnici</h1>
    <br><br>

    <div class="button_container">
        {{ html()->button('<img src="' . asset('img/icona_cestino.svg') . '" class="icon"> Elimina')->id('bottone_elimina')->name('bottone_elimina')->class('btn-alternativo-noborder') ->style('display: none;')  }}
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Modifica')->id('bottone_modifica')->name('bottone_modifica')->class('btn-alternativo-noborder') ->style('display: none;') }}
        <a href="{{ route('registrazione_tecnico_admin') }}" class="btn-alternativo-noborder"> <img src="{{ asset('img/plus_icon.svg') }}" class="icon"> Inserisci </a>
    </div>
    <br><br>

    <div class="table-scroll-container">
    @isset($tecnici)
        @if($tecnici->isNotEmpty())
        <table class="stile_tabella_checkbox">
            @foreach($tecnici as $user)
            <tr>
                <td>{{ html()->checkbox('ids[]', false, $user->username)->id($user->username) }}</td>
                <td>{{ $user->nome }}</td>
                <td>{{ $user->cognome }}</td>
            </tr>
            @endforeach
        </table>
        @else
        <p>Non ci sono tecnici da visualizzare</p>
        @endif
    @endisset()

    {{ html()->form()->close() }}
    </div>
</div>
@endsection

