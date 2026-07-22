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
                'password' => Hash::make('1'), // Hash della password
                'nome' => 'Mario',
                'cognome' => 'Rossi',
                'role' => 'staff'
            ],
            [
                'username' => 'staff2',
                'password' => Hash::make('1'),
                'nome' => 'Luca',
                'cognome' => 'Bianchi',
                'role' => 'staff'
            ],
            [
                'username' => 'tecntecn',
                'password' => Hash::make('V0shV0sh'),
                'nome' => 'Giulia',
                'cognome' => 'Verdi',
                'role' => 'tecnico'
            ],
            [
                'username' => 'staffstaff',
                'password' => Hash::make('V0shV0sh'),
                'nome' => 'Sara',
                'cognome' => 'Neri',
                'role' => 'staff'
            ],
            [
                'username' => 'adminadmin',
                'password' => Hash::make('V0shV0sh'),
                'nome' => 'Admin',
                'cognome' => 'Admin',
                'role' => 'admin'
            ],
            [
                'username' => 'tecnico1',
                'password' => Hash::make('1'),
                'nome' => 'Giulia',
                'cognome' => 'Verdi',
                'role' => 'tecnico'
            ],
            [
                'username' => 'tecnico2',
                'password' => Hash::make('1'),
                'nome' => 'Sara',
                'cognome' => 'Neri',
                'role' => 'tecnico'
            ],
            [
                'username' => 'admin',
                'password' => Hash::make('1'),
                'nome' => 'Admin',
                'cognome' => 'Admin',
                'role' => 'admin'
            ],
        ]);

        DB::table('staff')->insert([
            [
                'username' => 'staff1',
                
            ],
            [
                'username' => 'staff2',
                
            ],
            [
                'username' => 'staffstaff',
                
            ],
            
        ]);

        DB::table('centro_assistenza')->insert([
            [
                'nome' => 'Centro Assistenza Apple Roma',
                'indirizzo' => 'Via Roma 123, Roma',
            ],
            [
                'nome' => 'Centro Assistenza Milano',
                'indirizzo' => 'Corso Milasno 45, Milano',
            ],
            [
                'nome' => 'Centro Assistenza Napoli',
                'indirizzo' => 'Piazza Napoli 12, Napoli',
            ],
            [
                'nome' => 'Centro Assistenza Torino',
                'indirizzo' => 'Via Torino 89, Torino',
            ],[
                'nome' => 'Centro Assistenza Bologna',
                'indirizzo' => 'Corso Stamira 45, Bologna',
            ],
        ]);

        
        
        // Recupera gli ID generati per i centri di assistenza
        $romaId = DB::table('centro_assistenza')->where('nome', 'Centro Assistenza Apple Roma')->value('id');
        $milanoId = DB::table('centro_assistenza')->where('nome', 'Centro Assistenza Milano')->value('id');
        
        
        // Associa i tecnici ai centri di assistenza
        DB::table('tecnico')->insert([
            [
                'username' => 'tecnico1',
                'dataDiNascita' => '2000-01-01',
                'specializzazione' => 'Tecnico Certificato IOS',
                'id_centro_assistenza' => $romaId, // Associa al centro di Roma
            ],
            [
                'username' => 'tecnico2',
                'dataDiNascita' => '2000-04-01',
                'specializzazione' => 'Tecnico hardware',
                'id_centro_assistenza' => $milanoId, // Associa al centro di Milano
            ],
            [
                'username' => 'tecntecn',
                'dataDiNascita' => '2000-04-01',
                'specializzazione' => 'Tecnico hardware',
                'id_centro_assistenza' => $milanoId, // Associa al centro di Milano
            ],
        ]);
        // Inserimento dei prodotti e recupero degli ID generati
        $iphoneId = DB::table('prodotto')->insertGetId([
            'nome' => 'iPhone 14',
            'descrizione' => 'Smartphone di ultima generazione con display OLED e fotocamera avanzata.',
            'note_tecniche' => 'Capacità batteria: 3200mAh, Processore: A16 Bionic.',
            'modalita_installazione' => 'Configurazione guidata all’accensione del dispositivo.',
            'foto' => 'Iphone.png',
        ]);

        $macbookId = DB::table('prodotto')->insertGetId([
            'nome' => 'MacBook Pro 16"',
            'descrizione' => 'Laptop professionale con chip M1 Pro e display Retina XDR.',
            'note_tecniche' => 'Memoria: 16GB, Storage: 512GB SSD, Chip: M1 Pro.',
            'modalita_installazione' => 'Accensione e configurazione tramite macOS Setup Assistant.',
            'foto' => 'MacBook.png',
        ]);

        $appleWatchId = DB::table('prodotto')->insertGetId([
            'nome' => 'Apple Watch Series 8',
            'descrizione' => 'Smartwatch con funzioni avanzate di salute e fitness.',
            'note_tecniche' => 'Sensori: ECG, rilevamento cadute, SpO2.',
            'modalita_installazione' => 'Accoppia con iPhone tramite l’app Watch.',
            'foto' => 'AppleWatch.png',
        ]);
        
        $ipadId = DB::table('prodotto')->insertGetId([
            'nome' => 'iPad Air 5',
            'descrizione' => 'Tablet leggero e potente con chip M1 e display Liquid Retina.',
            'note_tecniche' => 'Chip: Apple M1, Display: 10.9", Archiviazione: 256GB.',
            'modalita_installazione' => 'Accendi il dispositivo e segui le istruzioni sullo schermo.',
            'foto' => 'Ipad.png',
        ]);


        $imacId = DB::table('prodotto')->insertGetId([
            'nome' => 'iMac 24" M1',
            'descrizione' => 'Desktop all-in-one con processore M1 e display Retina 4.5K.',
            'note_tecniche' => 'Memoria: 8GB, Archiviazione: 256GB SSD, GPU 8-core.',
            'modalita_installazione' => 'Accendi e configura tramite macOS Setup Assistant.',
            'foto' => 'MacBook.png',
        ]);

        $homepodId = DB::table('prodotto')->insertGetId([
            'nome' => 'HomePod Mini',
            'descrizione' => 'Speaker intelligente con Siri e audio a 360 gradi.',
            'note_tecniche' => 'Chip S5, Audio a 360°, Supporto per HomeKit.',
            'modalita_installazione' => 'Accoppia con l’iPhone tramite l’app Casa.',
            'foto' => 'HomePod.png',
        ]);

        $macStudioId = DB::table('prodotto')->insertGetId([
            'nome' => 'Mac Studio M1 Ultra',
            'descrizione' => 'Computer desktop potente con chip M1 Ultra.',
            'note_tecniche' => 'CPU 20-core, GPU 64-core, 128GB RAM.',
            'modalita_installazione' => 'Accendi e configura tramite macOS Setup Assistant.',
            'foto' => 'MacBook.png',
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
                'nome' => 'Schermo curvo',
                'descrizione' => 'Lo schermo è curvo e non risponde al tocco.',
                'nome_soluzione' => 'Sostituzione dello schermo',
                'descrizione_soluzione' => 'Rimuovere lo schermo curvo e installarne uno nuovo.',
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
            [
                'nome' => 'Display non risponde',
                'descrizione' => 'Il display dell’iPad non risponde al tocco o è bloccato.',
                'nome_soluzione' => 'Riavvio forzato',
                'descrizione_soluzione' => 'Riavvia il dispositivo premendo il pulsante di accensione e il tasto volume.',
                'id_prodotto' => $ipadId,
            ],
            [
                'nome' => 'Mac lento',
                'descrizione' => 'Il Mac è lento o si blocca frequentemente.',
                'nome_soluzione' => 'Pulizia del sistema',
                'descrizione_soluzione' => 'Libera spazio sul disco e aggiorna macOS.',
                'id_prodotto' => $imacId,
            ],
            [
                'nome' => 'Nessuna risposta vocale',
                'descrizione' => 'HomePod non risponde ai comandi vocali.',
                'nome_soluzione' => 'Riavvio di HomePod',
                'descrizione_soluzione' => 'Scollega l’alimentazione e ricollega il dispositivo dopo 10 secondi.',
                'id_prodotto' => $homepodId,
            ],
            [
                'nome' => 'Surriscaldamento',
                'descrizione' => 'Il dispositivo si surriscalda durante l’uso intenso.',
                'nome_soluzione' => 'Ventilazione migliorata',
                'descrizione_soluzione' => 'Pulire le ventole o posizionare il dispositivo in un’area ben ventilata.',
                'id_prodotto' => $macStudioId,
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


