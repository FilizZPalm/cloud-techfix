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
        Schema::create('malfunzionamento', function (Blueprint $table) {
            $table->id();
            $table->string('nome');
            $table->text('descrizione');
            $table->text('nome_soluzione')->nullable();  // Reso nullable
            $table->text('descrizione_soluzione')->nullable();  // Reso nullable
            $table->unsignedBigInteger('id_prodotto');
            $table->foreign('id_prodotto')->references('id')->on('prodotto')->onDelete('cascade')->onUpdate('cascade');

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
        Schema::dropIfExists('malfunzionamento');
    }
};