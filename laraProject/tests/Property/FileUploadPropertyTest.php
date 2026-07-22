<?php

namespace Tests\Property;

use Tests\TestCase;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * Property 12: File non-immagine rifiutati con HTTP 422, senza salvataggio
 *
 * Per qualsiasi file con estensione non-immagine, un tentativo di upload tramite
 * il form prodotto deve essere rifiutato con HTTP 422, senza che il file venga
 * salvato nel volume di storage.
 *
 * **Validates: Requirements 11.7**
 */
class FileUploadPropertyTest extends TestCase
{
    use RefreshDatabase;
    /**
     * Non-image file extensions to test (diverse set for property coverage).
     */
    private function getNonImageExtensions(): array
    {
        return [
            'pdf', 'txt', 'exe', 'doc', 'docx', 'zip', 'rar', 'tar', 'gz',
            'sh', 'bat', 'py', 'php', 'js', 'html', 'css', 'xml', 'json',
            'csv', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'mp3', 'mp4',
            'avi', 'mov', 'mkv', 'wav', 'flac', 'ogg', 'dll', 'so', 'bin',
            'iso', 'dmg', 'deb', 'rpm', 'apk', 'jar', 'class', 'sql', 'db',
            'log', 'cfg', 'ini', 'yml', 'yaml', 'toml', 'env', 'bak', 'tmp',
        ];
    }

    /**
     * Generate a random non-image filename with the given extension.
     */
    private function generateRandomFilename(string $extension): string
    {
        return 'test_upload_' . bin2hex(random_bytes(8)) . '.' . $extension;
    }

    /**
     * @test
     *
     * Property 12: Non-image files are rejected with HTTP 422, no file saved.
     *
     * **Validates: Requirements 11.7**
     *
     * Generates 100 files with non-image extensions, authenticates as admin
     * (who can access the product upload endpoint), and verifies:
     * 1. HTTP 422 response for each non-image file upload attempt
     * 2. No file is saved to public storage after rejection
     */
    public function test_property12_non_image_files_rejected_with_422_no_storage(): void
    {
        // Authenticate as admin user (required to access /crea_prodotto endpoint).
        // The route /crea_prodotto uses middleware 'can:isAdmin', so we need
        // an admin user to reach the validation layer.
        // Requirement 11.7 specifies "Staff autenticato" but the actual upload
        // endpoint is admin-only. We test the validation logic is enforced.
        $admin = User::where('role', 'admin')->first();

        if (!$admin) {
            $admin = new User();
            $admin->username = 'admin_test';
            $admin->password = bcrypt('password');
            $admin->nome = 'Admin';
            $admin->cognome = 'Test';
            $admin->role = 'admin';
            $admin->save();
        }

        $extensions = $this->getNonImageExtensions();
        $iterations = 100;
        $testedExtensions = [];

        for ($i = 0; $i < $iterations; $i++) {
            // Pick a random non-image extension
            $extension = $extensions[array_rand($extensions)];
            $testedExtensions[] = $extension;
            $filename = $this->generateRandomFilename($extension);

            // Create a fake file with the non-image extension
            $file = UploadedFile::fake()->create($filename, 100, 'application/octet-stream');

            // Attempt upload to the product creation endpoint.
            // Use withHeader('Accept', 'application/json') to get a 422 response
            // instead of a 302 redirect when validation fails.
            $response = $this->actingAs($admin)
                ->withHeader('Accept', 'application/json')
                ->post(route('crea_prodotto'), [
                    'nome' => 'Test Prodotto ' . $i,
                    'descrizione' => 'Descrizione di test per property 12',
                    'modalita_installazione' => 'Installazione standard',
                    'note_tecniche' => 'Note tecniche di test',
                    'foto' => $file,
                ]);

            // Assert HTTP 422 (validation error)
            $this->assertEquals(
                422,
                $response->getStatusCode(),
                "Expected HTTP 422 for file with extension '.{$extension}' (iteration {$i}), got {$response->getStatusCode()}"
            );

            // Assert no file was saved to the public product images directory
            $publicPath = public_path('img/prodotti');
            if (is_dir($publicPath)) {
                $savedFiles = glob($publicPath . '/*.' . $extension);
                $this->assertEmpty(
                    $savedFiles,
                    "File with extension '.{$extension}' should NOT have been saved to storage (iteration {$i})"
                );
            }
        }

        // Verify we tested at least 20 distinct extensions across 100 iterations
        $uniqueExtensions = array_unique($testedExtensions);
        $this->assertGreaterThanOrEqual(
            20,
            count($uniqueExtensions),
            'Property test should cover at least 20 distinct non-image extensions'
        );
    }
}
