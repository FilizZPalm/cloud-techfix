@extends(auth()->check() && auth()->user()->role === 'tecnico' ? 'layouts.tecnico_template' : 'layouts.public_template')

@section('title', 'centri_di_assistenza')

@section('cur_page','CENTRI ASSISTENZA')

@section('content')

<div class="catalogo-container">
    <h1>Centri di Assistenza</h1>

    @isset($centri_assistenza)
        @if($centri_assistenza->isNotEmpty())
        
            <!-- Contenitore scrollabile -->
            <div class="table-scroll-container">
                <table class="stile_tabella"> 
                    @foreach($centri_assistenza as $centri_assistenza)
                        <tr>
                            <td>{{ $centri_assistenza->nome }}</td>
                            <td>{{ $centri_assistenza->indirizzo }}</td>
                        </tr>
                    @endforeach
                </table>
            </div>
        
        @endif
    @endisset

</div>

@endsection
