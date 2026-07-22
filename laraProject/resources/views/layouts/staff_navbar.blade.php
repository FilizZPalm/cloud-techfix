<nav id="navBar" class="nav_bar">
    <table>
        <tr>
            @php
            $names = ['CATALOGO','LOGOUT'];
            $pages = ['catalogo','logout'];
            @endphp

            @foreach ($pages as $index => $page)
                @if ($names[$index] == $cur_page)
                    <td class="item_selected"><a href="{{ route($page) }}">{{ $names[$index] }}</a></td>
                @else
                <td class="item_not_selected">
                    <form action="{{ route('logout') }}" method="POST">
                         @csrf <!-- Aggiungi il token CSRF per sicurezza -->
                        <button type="submit" id="logout">{{ $names[1] }}</button>
                    </form>
                </td>
                @endif
            @endforeach
        </tr>
    </table>
</nav>