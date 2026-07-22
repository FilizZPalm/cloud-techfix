<nav id="navBar" class="nav_bar">
    <table>
        <tr>
            @php
            $names = ['TECNICI', 'STAFF', 'CATALOGO', 'CENTRI ASSISTENZA', 'LOGOUT'];
            $pages = ['gestisci_tecnici_admin', 'gestisci_staff_admin', 'catalogo', 'gestisci_centri_assistenza_admin', 'logout'];
            @endphp

            {{-- Ciclo per le voci di navigazione --}}
            @foreach ($pages as $index => $page)
                <td class="{{ $names[$index] == $cur_page ? 'item_selected' : 'item_not_selected' }}">
                    @if ($names[$index] == 'LOGOUT')
                        <!-- Form di logout quando è la voce LOGOUT -->
                        <form action="{{ route('logout') }}" method="POST">
                            @csrf
                            <button type="submit" id="logout">{{ $names[$index] }}</button>
                        </form>
                    @else
                        <!-- Link normale per le altre voci -->
                        <a href="{{ route($page) }}">{{ $names[$index] }}</a>
                    @endif
                </td>
            @endforeach
        </tr>
    </table>
</nav>