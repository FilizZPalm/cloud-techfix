@extends('layouts.admin_template')

@section('title', 'Visualizza staff admin')

@section('cur_page', 'STAFF')


@section('content')

<div class="catalogo-container">
    {{ html()->form()->route('gestisci_form_staff2',['username' => $staff->username])->open() }}
    <h1>Dettagli Staff</h1>

    <div class="button_container">
   
        {{ html()->submit('<img src="' . asset('img/pencil_icon.svg') . '" class="icon"> Modifica')->id('bottone_modifica ')->name('bottone_modifica')->class('btn-alternativo-noborder')  }}
        {{ html()->submit('<img src="' . asset('img/gestisci_prodotto.svg') . '" class="icon"> Gestisci Prodotto')->id('bottone_gestisci_prodotto ')->name('bottone_gestisci_prodotto')->class('btn-alternativo-noborder')  }}
    </div>

    <div class="stile_tabella">  
        {{ html()->label('Nome', 'nome')->class('stile_tabella_html_title') }}
        {{ html()->label('Nome:')->text($staff->nome)->class('stile_tabella_html_text')  }}
     </div>

     <div class="stile_tabella"> 

        {{ html()->label('Cognome', 'cognome')->class('stile_tabella_html_title') }}
        {{ html()->label('Cognome:')->text($staff->cognome)->class('stile_tabella_html_text') }}
     </div>

    <div class="stile_tabella">  
        {{ html()->label('Username', 'username')->class('stile_tabella_html_title') }}
        {{ html()->label('Username:')->text($staff->username)->class('stile_tabella_html_text') }}
      
    </div>

    


  

    <h1>Prodotti Associati</h1>
    @if($prodotti->isEmpty())
        <p>Nessun prodotto associato a questo staff.</p>
    @else
        <table class="stile_tabella_checkbox">
            <thead>
                <tr>
                    <th>ID Prodotto</th>
                    <th>Nome Prodotto</th>
                    <th>Descrizione</th>
                </tr>
            </thead>
            <tbody>
                @foreach ($prodotti as $prodotto)
                <tr>
                    <td>{{ $prodotto->id }}</td>
                    <td>{{ $prodotto->nome }}</td>
                    <td>{{ $prodotto->descrizione }}</td>
                </tr>
                @endforeach
            </tbody>
        </table>
    @endif

    {{ html()->form()->close() }}
</div>
@endsection
