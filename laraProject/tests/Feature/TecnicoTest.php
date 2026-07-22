<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Resources\Prodotto;
use App\Models\Resources\Malfunzionamento;
use App\Models\Resources\CentroAssistenza;
use App\Models\Resources\Tecnico;
use Illuminate\Foundation\Testing\RefreshDatabase;

class TecnicoTest extends TestCase
{
    use RefreshDatabase;

    private User $tecnico;
    private Prodotto $prodotto;

    protected function setUp(): void
    {
        parent::setUp();

        // Create a centro di assistenza
        $centro = CentroAssistenza::create([
            'id' => 1,
            'nome' => 'Centro Test',
            'indirizzo' => 'Via Test 1',
        ]);

        // Create a tecnico user
        $this->tecnico = User::create([
            'username' => 'tecnico_test',
            'password' => bcrypt('password'),
            'nome' => 'Mario',
            'cognome' => 'Rossi',
            'role' => 'tecnico',
        ]);

        Tecnico::create([
            'username' => 'tecnico_test',
            'dataDiNascita' => '1990-01-01',
            'specializzazione' => 'Tecnico hardware',
            'id_centro_assistenza' => $centro->id,
        ]);

        // Create a product
        $this->prodotto = Prodotto::create([
            'id' => 1,
            'nome' => 'iPhone 15',
            'descrizione' => 'Smartphone Apple di ultima generazione con display OLED',
            'note_tecniche' => 'Display 6.1 pollici, chip A16',
            'modalita_installazione' => 'Nessuna installazione richiesta',
            'foto' => 'iphone15.jpg',
        ]);

        // Create malfunzionamenti for the product
        Malfunzionamento::create([
            'id' => 1,
            'nome' => 'Schermo nero',
            'descrizione' => 'Lo schermo non si accende dopo aggiornamento',
            'nome_soluzione' => 'Reset hardware',
            'descrizione_soluzione' => 'Tenere premuto power + volume giù per 10 secondi',
            'id_prodotto' => $this->prodotto->id,
        ]);

        Malfunzionamento::create([
            'id' => 2,
            'nome' => 'Batteria scarica',
            'descrizione' => 'La batteria si scarica rapidamente dopo aggiornamento iOS',
            'nome_soluzione' => null,
            'descrizione_soluzione' => null,
            'id_prodotto' => $this->prodotto->id,
        ]);
    }

    /**
     * Test: GET catalogo returns 200 for authenticated tecnico.
     * Validates: Requirements 11.1
     */
    public function test_tecnico_can_access_catalogo(): void
    {
        $response = $this->actingAs($this->tecnico)->get('/catalogo');

        $response->assertStatus(200);
    }

    /**
     * Test: GET product detail page loads and contains product context.
     * The malfunzionamenti list is loaded via AJAX, so we verify the page
     * renders correctly and the AJAX endpoint returns the expected data.
     * Validates: Requirements 11.1
     */
    public function test_tecnico_can_view_product_detail_with_malfunzionamenti(): void
    {
        // The main page loads with HTTP 200 and contains the product ID for AJAX
        $response = $this->actingAs($this->tecnico)
            ->get('/malfunzionamenti/' . $this->prodotto->id);

        $response->assertStatus(200);
        $response->assertSee('Malfunzionamenti');

        // The AJAX endpoint returns malfunzionamenti for this product
        $ajaxResponse = $this->actingAs($this->tecnico)
            ->get('/filtra-malfunzionamenti?prodotto_id=' . $this->prodotto->id);

        $ajaxResponse->assertStatus(200);
        $ajaxResponse->assertJson([]);
        $content = $ajaxResponse->getContent();
        $this->assertStringContainsString('Schermo nero', $content);
        $this->assertStringContainsString('Batteria scarica', $content);
    }

    /**
     * Test: AJAX endpoint returns repair solutions when available.
     * Validates: Requirements 11.1
     */
    public function test_tecnico_can_see_repair_solutions(): void
    {
        $ajaxResponse = $this->actingAs($this->tecnico)
            ->get('/filtra-malfunzionamenti?prodotto_id=' . $this->prodotto->id);

        $ajaxResponse->assertStatus(200);
        $content = $ajaxResponse->getContent();
        $this->assertStringContainsString('Reset hardware', $content);
    }

    /**
     * Test: GET non-existing product returns 404.
     */
    public function test_tecnico_gets_404_for_nonexistent_product(): void
    {
        $response = $this->actingAs($this->tecnico)
            ->get('/malfunzionamenti/9999');

        $response->assertStatus(404);
    }
}
