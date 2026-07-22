<nav id="navBar" class="nav_bar">
    <table>
        <tr> 
            @php
                $names = ['HOME', 'CATALOGO', 'CENTRI ASSISTENZA', 'LOGIN'];
                $pages = ['home', 'catalogo', 'centri_di_assistenza', 'login']
            @endphp

            @for ($i = 0; $i < 3; $i++)              
                @if ($names[$i] == $cur_page)
                    <td class="item_selected"><a href="{{ route($pages[$i]) }}">{{$names[$i]}}</a></td>
                @else
                    <td class="item_not_selected"><a href="{{ route($pages[$i]) }}">{{$names[$i]}}</a></td>
                @endif
            @endfor
            
            @guest
                @if ($names[$i] == $cur_page)
                    <td class="item_selected"><a href="{{ route($pages[$i]) }}">{{$names[$i]}}</a></td>
                @else
                    <td class="item_not_selected"><a href="{{ route($pages[$i]) }}">{{$names[$i]}}</a></td>
                @endif
            @endguest
        </tr>
    </table>
</nav>