<?php

namespace Database\Seeders;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder {

    /**
     * Run the database seeds.
     */
    
    public function run(): void {
        DB::table('user')->insert([
            [
                'username' => 'staff1',
                'password' => Hash::make('password1'), // Hash della password
                'nome' => 'Mario',
                'cognome' => 'Rossi',
                'role' => 'staff'
            ],
            [
                'username' => 'staff2',
                'password' => Hash::make('password2'),
                'nome' => 'Luca',
                'cognome' => 'Bianchi',
                'role' => 'staff'
            ],
            [
                'username' => 'tecnico1',
                'password' => Hash::make('password1'),
                'nome' => 'Giulia',
                'cognome' => 'Verdi',
                'role' => 'tecnico'
            ],
            [
                'username' => 'tecnico2',
                'password' => Hash::make('password2'),
                'nome' => 'Sara',
                'cognome' => 'Neri',
                'role' => 'tecnico'
            ],
        ]);

        DB::table('staff')->insert([
            [
                'username' => 'staff1',
                
            ],
            [
                'username' => 'staff2',
                
            ],
        ]);

        DB::table('tecnico')->insert([
            [
                'username' => 'tecnico1',
                'dataDiNascita' => '2000-01-01',
                'specializzazione' => 'Tecnico Certificato IOS'
            ],
            [
                'username' => 'tecnico2',
                'dataDiNascita' => '2000-04-01',
                'specializzazione' => 'Tecnico hardware'
            ],
        ]);

        DB::table('centro_assistenza')->insert([
            [
                'nome' => 'Centro Assistenza Apple Roma',
                'indirizzo' => 'Via Roma 123, Roma',
            ],
            [
                'nome' => 'Centro Assistenza Milano',
                'indirizzo' => 'Corso Milano 45, Milano',
            ],
            [
                'nome' => 'Centro Assistenza Napoli',
                'indirizzo' => 'Piazza Napoli 12, Napoli',
            ],
            [
                'nome' => 'Centro Assistenza Torino',
                'indirizzo' => 'Via Torino 89, Torino',
            ],
        ]);
        
        // Inserimento dei prodotti e recupero degli ID generati
        $iphoneId = DB::table('prodotto')->insertGetId([
            'nome' => 'iPhone 14',
            'descrizione' => 'Smartphone di ultima generazione con display OLED e fotocamera avanzata.',
            'note_tecniche' => 'Capacità batteria: 3200mAh, Processore: A16 Bionic.',
            'modalita_installazione' => 'Configurazione guidata all’accensione del dispositivo.',
            'foto' => '/images/products/iphone14.jpg',
        ]);

        $macbookId = DB::table('prodotto')->insertGetId([
            'nome' => 'MacBook Pro 16"',
            'descrizione' => 'Laptop professionale con chip M1 Pro e display Retina XDR.',
            'note_tecniche' => 'Memoria: 16GB, Storage: 512GB SSD, Chip: M1 Pro.',
            'modalita_installazione' => 'Accensione e configurazione tramite macOS Setup Assistant.',
            'foto' => '/images/products/macbookpro16.jpg',
        ]);

        $appleWatchId = DB::table('prodotto')->insertGetId([
            'nome' => 'Apple Watch Series 8',
            'descrizione' => 'Smartwatch con funzioni avanzate di salute e fitness.',
            'note_tecniche' => 'Sensori: ECG, rilevamento cadute, SpO2.',
            'modalita_installazione' => 'Accoppia con iPhone tramite l’app Watch.',
            'foto' => '/images/products/applewatch8.jpg',
        ]);

        // Inserimento dei malfunzionamenti con riferimento agli ID dei prodotti
        DB::table('malfunzionamento')->insert([
            [
                'nome' => 'Schermo rotto',
                'descrizione' => 'Lo schermo è incrinato o non risponde al tocco.',
                'nome_soluzione' => 'Sostituzione dello schermo',
                'descrizione_soluzione' => 'Rimuovere lo schermo rotto e installarne uno nuovo.',
                'id_prodotto' => $iphoneId,
            ],
            [
                'nome' => 'Problema batteria',
                'descrizione' => 'La batteria si scarica rapidamente o non si ricarica.',
                'nome_soluzione' => 'Sostituzione della batteria',
                'descrizione_soluzione' => 'Sostituire la batteria con una nuova.',
                'id_prodotto' => $macbookId,
            ],
            [
                'nome' => 'Errore software',
                'descrizione' => 'Il dispositivo si blocca frequentemente o presenta errori.',
                'nome_soluzione' => 'Aggiornamento software',
                'descrizione_soluzione' => 'Ripristinare il software e aggiornare all’ultima versione.',
                'id_prodotto' => $appleWatchId,
            ],
        ]);

        DB::table('accesso_prodotto')->insert([
            [
                'id_prodotto' => $iphoneId, 
                'username_staff' =>  'staff1', 
            ],
            [
                'id_prodotto' => $macbookId, 
                'username_staff' => 'staff2',
            ],
            [
                'id_prodotto' => $appleWatchId,
                'username_staff' => 'staff1',
            ],
        ]);
    
    }
}


