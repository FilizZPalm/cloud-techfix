@extends('layouts.admin_template')

@section('title', 'Assegna Prodotti Staff')

@section('cur_page', 'STAFF')

@section('content')

<div class="catalogo-container">

    {{ html()->form()->route('assegna_prodotti_staff_admin', ['username' => $staff->username])->open() }}
    @csrf
    <h1>Prodotti Disponibili</h1>
    <br><br>

    

    <div class="table-scroll-container">
    @isset($prodottiDisponibili)
        @if($prodottiDisponibili->isNotEmpty())
        <table class="stile_tabella_checkbox">
            @foreach ($prodottiDisponibili as $prodotto)
            <tr>
                <td>{{ html()->checkbox('ids[]', false, $prodotto->id)->id($prodotto->id) }}</td>
                <td>{{ $prodotto->id }}</td>
                <td>{{ $prodotto->nome }}</td>
                <td>{{ $prodotto->descrizione }}</td>
            </tr>
            @endforeach
        </table>
        @else
        <p>Nessun prodotto disponibile per l'assegnazione.</p>
        @endif
    @endisset()
    </div>

    <div class="button_container">
        {{ html()->submit('Assegna Prodotti')->id('bottone_assegna_prodotti')->name('bottone_assegna_prodotti')->class('btn-alternativo-noborder') }}
    </div>
    <br><br>

    {{ html()->form()->close() }}
    <a href="{{ route('gestione_prodotti_staff_admin',['username' => $staff->username]) }}" class="btn-alternativo-noborder"><img  src="{{ asset('img/go_back_arrow.svg') }}" class="icon">Indietro</a>
</div>



@endsection
