@extends('layouts.admin_template')

@section('title', 'Gestisci Prodotti Staff')

@section('cur_page', 'STAFF')

@section('content')
<script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
<script src="{{ asset('js/show_hide.js') }}"></script>

<div class="catalogo-container">

    {{ html()->form()->route('rimuovi_prodotto_staff',['username' => $staff->username])->open() }}
    @csrf
    <h1>Prodotti Associati</h1>
    <br><br>

    <div class="button_container">
    {{ html()->button('<img src="' . asset('img/icona_cestino.svg') . '" class="icon"> Rimuovi prodotto')->id('bottone_rimuovi_prodotto')->name('bottone_rimuovi_prodotto')->class('btn-alternativo-noborder')   }}
    <a href="{{ route('assegna_prodotti_staff_admin',['username' => $staff->username]) }}" class="btn-alternativo-noborder"> <img src="{{ asset('img/plus_icon.svg') }}" class="icon"> Assegna nuovo Prodotto </a>
    </div>
    <br><br>

    <div class="table-scroll-container">
    @isset($prodotti)
        @if($prodotti->isNotEmpty())
        <table class="stile_tabella_checkbox">
                @foreach ($prodotti as $prodotto)
                <tr>
                    <td>{{ html()->checkbox('ids[]', false, $prodotto->id)->id($prodotto->id) }}</td>
                    <td>{{ $prodotto->id }}</td>
                    <td>{{ $prodotto->nome }}</td>
                    <td>{{ $prodotto->descrizione }}</td>
                </tr>
                @endforeach
        </table>
        @else
        <p>Nessun prodotto associato a {{ $staff->nome }}.</p>
        @endif
    @endisset()


    </div>
    {{ html()->form()->close() }}

    <a href="{{ route('visualizza_account_staff_admin',['username' => $staff->username]) }}" class="btn-alternativo-noborder"><img  src="{{ asset('img/go_back_arrow.svg') }}" class="icon">Indietro</a>
</div>
@endsection
