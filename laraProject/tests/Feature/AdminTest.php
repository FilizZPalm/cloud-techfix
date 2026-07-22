<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Resources\CentroAssistenza;
use App\Models\Resources\Tecnico;
use App\Models\Resources\Staff;
use App\Models\Resources\Prodotto;
use App\Models\Resources\AccessoProdotto;
use Illuminate\Foundation\Testing\RefreshDatabase;

class AdminTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private CentroAssistenza $centro;

    protected function setUp(): void
    {
        parent::setUp();

        // Create admin user
        $this->admin = User::create([
            'username' => 'admin',
            'password' => bcrypt('adminadmin'),
            'nome' => 'Admin',
            'cognome' => 'Sistema',
            'role' => 'admin',
        ]);

        // Create a centro di assistenza
        $this->centro = CentroAssistenza::create([
            'id' => 1,
            'nome' => 'Centro Milano',
            'indirizzo' => 'Via Roma 10, Milano',
        ]);

        // Create a staff user
        $staffUser = User::create([
            'username' => 'staff1',
            'password' => bcrypt('staffstaff'),
            'nome' => 'Marco',
            'cognome' => 'Bianchi',
            'role' => 'staff',
        ]);
        Staff::create(['username' => 'staff1']);

        // Create a tecnico user
        $tecnicoUser = User::create([
            'username' => 'tecnico1',
            'password' => bcrypt('tecnicotecnico'),
            'nome' => 'Paolo',
            'cognome' => 'Neri',
            'role' => 'tecnico',
        ]);
        Tecnico::create([
            'username' => 'tecnico1',
            'dataDiNascita' => '1985-05-15',
            'specializzazione' => 'Tecnico hardware',
            'id_centro_assistenza' => $this->centro->id,
        ]);

        // Create a product
        Prodotto::create([
            'id' => 1,
            'nome' => 'iPad Air',
            'descrizione' => 'Tablet Apple versatile con chip M1 per lavoro e intrattenimento',
            'note_tecniche' => 'Display 10.9, chip M1',
            'modalita_installazione' => 'Setup guidato',
            'foto' => 'ipad.jpg',
        ]);
    }

    // --- CRUD Centri di Assistenza ---

    /**
     * Test: Admin can view centri di assistenza list → 200.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_view_centri_assistenza(): void
    {
        $response = $this->actingAs($this->admin)
            ->get('/gestisci_centri_assistenza_admin');

        $response->assertStatus(200);
        $response->assertSee('Centro Milano');
    }

    /**
     * Test: Admin can create a new centro di assistenza → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_create_centro_assistenza(): void
    {
        $response = $this->actingAs($this->admin)->post('/crea_centro_assistenza', [
            'nome' => 'Centro Napoli',
            'indirizzo' => 'Via Toledo 5, Napoli',
        ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('centro_assistenza', [
            'nome' => 'Centro Napoli',
        ]);
    }

    /**
     * Test: Admin can update a centro di assistenza → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_update_centro_assistenza(): void
    {
        $response = $this->actingAs($this->admin)
            ->post('/modifica_centro_assistenza/' . $this->centro->id, [
                'nome' => 'Centro Milano Updated',
                'indirizzo' => 'Via Montenapoleone 1, Milano',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('centro_assistenza', [
            'id' => $this->centro->id,
            'nome' => 'Centro Milano Updated',
        ]);
    }

    /**
     * Test: Admin can delete centri di assistenza → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_delete_centro_assistenza(): void
    {
        // Create a separate centro without tecnici to delete cleanly
        $centroToDelete = CentroAssistenza::create([
            'id' => 2,
            'nome' => 'Centro Da Eliminare',
            'indirizzo' => 'Via Test 99',
        ]);

        $response = $this->actingAs($this->admin)
            ->post('/admin/gestisci_form_centro_assistenza', [
                'ids' => [$centroToDelete->id],
                'bottone_elimina' => 'elimina',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseMissing('centro_assistenza', [
            'id' => $centroToDelete->id,
        ]);
    }

    // --- CRUD Utenti (Tecnici) ---

    /**
     * Test: Admin can view tecnici list → 200.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_view_tecnici(): void
    {
        $response = $this->actingAs($this->admin)
            ->get('/gestisci_tecnici_admin');

        $response->assertStatus(200);
    }

    /**
     * Test: Admin can create a tecnico → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_create_tecnico(): void
    {
        $response = $this->actingAs($this->admin)->post('/crea_tecnico', [
            'nome' => 'Giuseppe',
            'cognome' => 'Verdi',
            'password' => 'password123',
            'dataDiNascita' => '1992-03-20',
            'specializzazione' => 'Tecnico Certificato IOS',
            'centroDiAssistenza' => $this->centro->id,
        ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('user', [
            'nome' => 'Giuseppe',
            'cognome' => 'Verdi',
            'role' => 'tecnico',
        ]);
    }

    /**
     * Test: Admin can delete tecnici → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_delete_tecnico(): void
    {
        $response = $this->actingAs($this->admin)
            ->post('/gestisci_form_tecnico', [
                'ids' => ['tecnico1'],
                'bottone_elimina' => 'elimina',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseMissing('user', [
            'username' => 'tecnico1',
        ]);
    }

    // --- CRUD Utenti (Staff) ---

    /**
     * Test: Admin can view staff list → 200.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_view_staff(): void
    {
        $response = $this->actingAs($this->admin)
            ->get('/gestisci_staff_admin');

        $response->assertStatus(200);
    }

    /**
     * Test: Admin can create a staff member → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_create_staff(): void
    {
        $response = $this->actingAs($this->admin)->post('/crea_staff', [
            'nome' => 'Anna',
            'cognome' => 'Blu',
            'password' => 'password123',
        ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('user', [
            'nome' => 'Anna',
            'cognome' => 'Blu',
            'role' => 'staff',
        ]);
    }

    /**
     * Test: Admin can delete staff → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_delete_staff(): void
    {
        $response = $this->actingAs($this->admin)
            ->post('/gestisci_form_staff', [
                'ids' => ['staff1'],
                'bottone_elimina' => 'elimina',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseMissing('user', [
            'username' => 'staff1',
        ]);
    }

    // --- Assegnazioni prodotto-staff ---

    /**
     * Test: Admin can view products assigned to staff → 200.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_view_staff_products(): void
    {
        // Assign a product to staff first
        AccessoProdotto::create([
            'id_prodotto' => 1,
            'username_staff' => 'staff1',
        ]);

        $response = $this->actingAs($this->admin)
            ->get('/gestione_prodotti_staff_admin/staff1');

        $response->assertStatus(200);
    }

    /**
     * Test: Admin can assign products to staff → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_assign_product_to_staff(): void
    {
        $response = $this->actingAs($this->admin)
            ->post('/assegna_prodotti_staff_admin/staff1', [
                'ids' => [1],
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseHas('accesso_prodotto', [
            'id_prodotto' => 1,
            'username_staff' => 'staff1',
        ]);
    }

    /**
     * Test: Admin can remove product assignment from staff → 302 redirect.
     * Validates: Requirements 11.3
     */
    public function test_admin_can_remove_product_from_staff(): void
    {
        // First assign the product
        AccessoProdotto::create([
            'id_prodotto' => 1,
            'username_staff' => 'staff1',
        ]);

        $response = $this->actingAs($this->admin)
            ->post('/rimuovi_prodotto_staff/staff1', [
                'ids' => [1],
                'bottone_rimuovi_prodotto' => 'rimuovi',
            ]);

        $response->assertStatus(302);
        $this->assertDatabaseMissing('accesso_prodotto', [
            'id_prodotto' => 1,
            'username_staff' => 'staff1',
        ]);
    }
}
