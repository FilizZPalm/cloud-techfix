@if($malfunzionamenti->isNotEmpty())
    <table class="stile_tabella"> 
        @foreach($malfunzionamenti as $malfunzionamento)
            <tr>
                <td>{{ $malfunzionamento->nome }}</td>
                <td>{{ $malfunzionamento->descrizione }}</td>
                <td>
                    <button 
                        class="product-button" 
                        onclick="mostraMalfunzionamento(this)"
                        data-id="{{ $malfunzionamento->id }}"
                        data-nome_prodotto="{{ $prodotto->nome }}"
                        data-nome="{{ $malfunzionamento->nome }}"
                        data-descrizione="{{ $malfunzionamento->descrizione }}"
                        data-nome_soluzione="{{ $malfunzionamento->nome_soluzione }}"
                        data-descrizione_soluzione="{{ $malfunzionamento->descrizione_soluzione }}"
                        
                    >
                        Dettagli &gt;
                    </button>
                </td>
            </tr>
        @endforeach
    </table>
@else
    <p>Nessun malfunzionamento trovato.</p>
@endif
