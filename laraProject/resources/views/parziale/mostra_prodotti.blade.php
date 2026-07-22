<div class="prodotti">
        @foreach($prodotti as $prodotto)
            <div class="product-row">
                <!-- Colonna 1: Immagine -->
                <div class="product-image-col">
                <img src="{{ asset('img/prodotti/' . $prodotto->foto) }}" alt="{{ $prodotto->nome }}" class="product-image">
                </div>

                <!-- Colonna 2: Nome e Descrizione -->
                <div class="product-info-col">
                    <h2>{{ $prodotto->nome }}</h2>
                    <p>{{ Str::limit($prodotto->descrizione, 120) }}</p>
                    <p><strong>Note Tecniche:</strong> {{ Str::limit($prodotto->note_tecniche, 120) }}</p>
                </div>

                <!-- Colonna 3: Bottone Scheda Tecnica -->
                <!-- Aggiungo i dati del prodotto come attributi del bottone -->
                <div class="product-button-col">
                    <button 
                        class="product-button" 
                        onclick="mostraSchedaTecnica(this)"
                        data-id="{{ $prodotto->id }}"
                        data-foto="{{ asset('img/prodotti/' . $prodotto->foto) }}"
                        data-nome="{{ $prodotto->nome }}"
                        data-descrizione="{{ $prodotto->descrizione }}"
                        data-modalita="{{ $prodotto->modalita_installazione }}"
                        data-note="{{ $prodotto->note_tecniche }}"
                    >
                        Scheda Tecnica &gt;
                    </button>
                </div>

            </div>
        @endforeach
    </div>


