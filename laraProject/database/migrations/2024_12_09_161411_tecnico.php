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
        Schema::create('tecnico', function (Blueprint $table) {
            $table->string('username')->primary();
            $table->date('dataDiNascita');
            $table->enum('specializzazione', [
                'Tecnico Certificato IOS',
                'Tecnico Certificato Apple',
                'Tecnico hardware',
                'Tecnico software'
            ]);
            $table->foreign('username')->references('username')->on('user')->onDelete('cascade')->onUpdate('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('tecnico');
    }
};
