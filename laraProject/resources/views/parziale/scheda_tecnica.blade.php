<!-- Template Nascosto -->
<template id="template-scheda-tecnica">
    <div class="scheda-tecnica-container">

        @auth
        
            @if(auth()->user()->role === 'admin')
                <!-- Contenuto per l'admin -->
                <h1 class="scheda-tecnica-title">Dettagli Prodotto</h1>


            <div class="button_container_scheda_tecnica">
                    <form method="POST" action="{{ route('gestisci_form_prodotto') }}">
                        @csrf
                        <input type="hidden" id="prodotto-id" name="id">
                        
                        <button type="submit" name="bottone_elimina" class="btn-alternativo-noborder">
                            <img src="{{ asset('img/icona_cestino.svg') }}" class="icon"> Elimina
                        </button>
                        <button type="submit" name="bottone_modifica" class="btn-alternativo-noborder">
                            <img src="{{ asset('img/pencil_icon.svg') }}" class="icon"> Modifica
                        </button>
                    </form>
            </div>

            @endif
         @endauth

         

        
        <!-- Contenuto per evitare errore nella home (l'id non ha posto dove essere inserito) -->
        <input type="hidden" id="prodotto-id" name="id">

        <!-- Immagine e Nome -->
        <div class="scheda-tecnica-header">
            <div class="scheda-tecnica-image">
                <img id="prodotto-foto">
            </div>

            <h2 id="prodotto-nome" class="scheda-tecnica-nome"></h2>
        </div>

        <!-- Informazioni Prodotto -->
        <div class="scheda-tecnica-info">
            <h3>Descrizione Completa</h3>
            <p id="prodotto-descrizione"></p>

            <h3>Modalità di Installazione</h3>
            <p id="prodotto-modalita"></p>

            <h3>Note Tecniche</h3>
            <p id="prodotto-note"></p>
        </div>

        <!-- Bottone per visualizzare i malfunzionamenti (solo se autenticato) -->
        @auth
            <div class="scheda-tecnica-button-col">
                <!--'id' viene messo come segnaposto, poi da sostutuire con un parametro (id del prodotto) -->
                <a href="#" id="visualizza-malfunzionamenti" class="scheda-tecnica-btn" data-url="{{ route('visualizza_malfunzionamenti', ['id' => '__ID__']) }}">
                    Malfunzionamenti
                </a>
            </div>
        @endauth

        <!-- Bottone per tornare al catalogo -->
        <div class="scheda-tecnica-button-col">
            <button class="scheda-tecnica-btn" onclick="tornaAlCatalogo()">Torna al Catalogo</button>
        </div>
    </div>
</template>
