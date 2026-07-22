<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('prodotto', function (Blueprint $table) {
            $table->id();
            $table->string('nome');
            $table->text('descrizione');
            $table->text('note_tecniche');
            $table->text('modalita_installazione');
            $table->string('foto'); 

            if (config('database.default') !== 'sqlite') {
                $table->fullText('descrizione');
            }
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('prodotto');
    }
};
