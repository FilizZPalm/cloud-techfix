<!-- Se c'è una sola pagina la paginazione non viene mostrata $paginate viene passato da paginate() nel controller-->
@if ($paginator->lastPage() != 1)
    <div class="pagination">
        <div id="pagination">
            @php
                $number_of_elements = 3;
                // Calcolo il blocco di pagine in cui mi trovo, 0-3 primo blocco, 4-3 secondo blocco
                $current_block = intdiv($paginator->currentPage() - 1, $number_of_elements);
            @endphp

            @if ($current_block != 0)
            <!--  se non siamo nel primo blocco, Mostra sempre il pulsante "1" (per tornare alla prima pagina). -->
                <a href="{{ $paginator->url(1) }}&termine={{ $termine }}"><div class="page_number_container">1</div></a>
              <!--  Mostra il pulsante "<" per tornare indietro al blocco precedente. -->
                <a href="{{ $paginator->url($current_block*$number_of_elements) }}&termine={{ $termine }}"><div class="page_number_container"><</div></a>
            @endif


            <!-- Il ciclo for mostra solo le pagine del blocco corrente. -->
            @for($i = $current_block*$number_of_elements + 1; $i <= $paginator->lastPage() && $i <= $current_block*$number_of_elements + $number_of_elements; $i++)
                <!-- Se $i è la pagina attuale, la evidenzia con class="page_number_selected". Altrimenti, genera un link alla pagina $i. -->
                @if ($i == $paginator->currentPage())
                    <div class="page_number_selected">{{ $i }}</div>
                @else
                    <a href="{{ $paginator->url($i) }}&termine={{ $termine }}"><div class="page_number_container">{{ $i }}</div></a>
                @endif
            @endfor
            <!-- Se non siamo nell'ultimo blocco, Mostra il pulsante ">" per andare avanti al blocco successivo. -->
            @if ($current_block != ceil($paginator->lastPage() / $number_of_elements) - 1)
            <!--  Verifica se il blocco successivo non è già l'ultimo blocco. Se non lo è, mostra il pulsante ">". -->
                @if($current_block*$number_of_elements + $number_of_elements != $paginator->lastPage()-1)
                    <a href="{{ $paginator->url($i) }}&termine={{ $termine }}"><div class="page_number_container">></div></a>
                @endif
                <!--  Mostra l'ultima pagina -->
                <a href="{{ $paginator->url($paginator->lastPage()) }}&termine={{ $termine }}"><div class="page_number_container">{{ $paginator->lastPage() }}</div></a>
            @endif
        </div>
    </div>
@endif
