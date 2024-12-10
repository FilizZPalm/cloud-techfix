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
        
        Schema::create('accesso_prodotto', function (Blueprint $table) {
            $table->unsignedBigInteger('id_prodotto');
            $table->string('username_staff');
            $table->foreign('id_prodotto')->references('id')->on('prodotto')->onDelete('cascade')->onUpdate('cascade');
            $table->foreign('username_staff')->references('username')->on('staff')->onDelete('cascade')->onUpdate('cascade');
            $table->primary(['id_prodotto','username_staff']);
        });

    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('accesso_prodotto');
    }
};
