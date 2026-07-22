<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Resources\Prodotto;
use App\Models\Resources\Malfunzionamento;
use App\Models\Resources\Staff;
use App\Models\Resources\AccessoProdotto;
use Illuminate\Foundation\Testing\RefreshDatabase;

class StaffTest extends TestCase
{
    use RefreshDatabase;

    private User $staffUser;
    private Prodotto $prodotto;
    private Malfunzionamento $malfunzionamento;

    protected function setUp(): void
    {
        parent::setUp();

        // Create a staff user
        $this->staffUser = User::create([
            'username' => 'staff_test',
            'password' => bcrypt('password'),
            'nome' => 'Luigi',
            'cognome' => 'Verdi',
            'role' => 'staff',
        ]);

        Staff::create([
            'username' => 'staff_test',
        ]);

        // Create a product
        $this->prodotto = Prodotto::create([
            'id' => 1,
            'nome' => 'MacBook Pro',
            'descrizione' => 'Laptop Apple professionale con chip M3 per sviluppatori',
            'note_tecniche' => 'Chip M3, 16GB RAM, 512GB SSD',
            'modalita_installazione' => 'Setup iniziale guidato',
            'foto' => 'macbook.jpg',
        ]);

        // Assign product to staff
        AccessoProdotto::create([
            'id_prodotto' => $this->prodotto->id,
            'username_staff' => 'staff_test',
        ]);

        // Create a malfunzionamento
        $this->malfunzionamento = Malfunzionamento::create([
            'id' => 1,
            'nome' => 'Kernel panic',
            'descrizione' => 'Il sistema si blocca con kernel panic durante utilizzo intensivo',
            'nome_soluzione' => null,
            'descrizione_soluzione' => null,
            'id_prodotto' => $this->prodotto->id,
        ]);
    }

    /**
     * Test: Staff can create a malfunzionamento (POST) → 302 redirect.
     * Validates: Requirements 11.2
     */
    public function test_staff_can_create_malfunzionamento(): void
    {
        $response = $this->actingAs($this->staffUser)->post('/salva-malfunzionamento', [
            'nome' => 'Surriscaldamento',
            'descrizione' => 'Il laptop si surriscalda durante la ricarica',
            'id_prodotto' => $this->prodotto->id,
        ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('malfunzionamento', [
            'nome' => 'Surriscaldamento',
            'id_prodotto' => $this->prodotto->id,
        ]);
    }

    /**
     * Test: Staff can access the malfunzionamento creation form.
     * Validates: Requirements 11.2
     */
    public function test_staff_can_access_create_malfunzionamento_form(): void
    {
        $response = $this->actingAs($this->staffUser)
            ->get('/registrazione_malfunzionamento_staff/' . $this->prodotto->id);

        $response->assertStatus(200);
    }

    /**
     * Test: Staff can update (modify) a malfunzionamento → 302 redirect.
     * Validates: Requirements 11.2
     */
    public function test_staff_can_update_malfunzionamento(): void
    {
        $response = $this->actingAs($this->staffUser)
            ->post('/aggiorna-malfunzionamento/' . $this->malfunzionamento->id, [
                'nome' => 'Kernel panic aggiornato',
                'descrizione' => 'Descrizione aggiornata del problema',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('malfunzionamento', [
            'id' => $this->malfunzionamento->id,
            'nome' => 'Kernel panic aggiornato',
        ]);
    }

    /**
     * Test: Staff can delete a malfunzionamento (POST with bottone_elimina) → 302 redirect.
     * Validates: Requirements 11.2
     */
    public function test_staff_can_delete_malfunzionamento(): void
    {
        $response = $this->actingAs($this->staffUser)
            ->post('/gestisci_form_malfunzionamento', [
                'id' => $this->malfunzionamento->id,
                'bottone_elimina' => 'elimina',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseMissing('malfunzionamento', [
            'id' => $this->malfunzionamento->id,
        ]);
    }

    /**
     * Test: Staff can update a soluzione for a malfunzionamento → 302 redirect.
     * Validates: Requirements 11.2
     */
    public function test_staff_can_update_soluzione(): void
    {
        $response = $this->actingAs($this->staffUser)
            ->post('/salva-modifica-soluzione/' . $this->malfunzionamento->id, [
                'nome_soluzione' => 'Aggiornamento firmware',
                'descrizione_soluzione' => 'Aggiornare il firmware alla versione più recente',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('malfunzionamento', [
            'id' => $this->malfunzionamento->id,
            'nome_soluzione' => 'Aggiornamento firmware',
        ]);
    }
}
