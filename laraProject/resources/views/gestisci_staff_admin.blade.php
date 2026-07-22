@extends('layouts.admin_template')

@section('title', 'Gestisci staff admin')

@section('cur_page', 'STAFF')


@section('content')
<script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
<script src="{{ asset('js/show_hide.js') }}"></script>

<div class="catalogo-container">
    {{ html()->form()->route('gestisci_form_staff')->open() }}
    @csrf
    <h1>Lista Staff</h1>
    <br><br>

    <div class="button_container">
        {{ html()->button('<img src="' . asset('img/icona_cestino.svg') . '" class="icon"> Elimina')->id('bottone_elimina')->name('bottone_elimina')->class('btn-alternativo-noborder') ->style('display: none;')  }}
        {{ html()->submit('<img src="' . asset('img/view_show.svg') . '" class="icon"> Visualizza Account')->id('bottone_visualizza_account')->name('bottone_visualizza_account')->class('btn-alternativo-noborder')  }}
        <a href="{{ route('registrazione_staff_admin') }}" class="btn-alternativo-noborder"> <img src="{{ asset('img/plus_icon.svg') }}" class="icon"> Inserisci </a>
    </div>
    <br><br>

    <div class="table-scroll-container">
    @isset($staff)
        @if($staff->isNotEmpty())
        <table class="stile_tabella_checkbox">
            @foreach($staff as $user)
            <tr>
                <td>{{ html()->checkbox('ids[]', false, $user->username)->id($user->username) }}</td>
                <td>{{ $user->nome }}</td>
                <td>{{ $user->cognome }}</td>
            </tr>
            @endforeach
        </table>
        @else
        <p>Non ci sono membri dello staff da visualizzare</p>
        @endif
    @endisset()

    {{ html()->form()->close() }}
    </div>
</div>
@endsection

