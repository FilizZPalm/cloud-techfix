-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Creato il: Lug 20, 2026 alle 16:02
-- Versione del server: 10.4.28-MariaDB
-- Versione PHP: 8.2.4

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `grp_61_db`
--

-- --------------------------------------------------------

--
-- Struttura della tabella `accesso_prodotto`
--

CREATE TABLE `accesso_prodotto` (
  `id_prodotto` bigint(20) UNSIGNED NOT NULL,
  `username_staff` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `accesso_prodotto`
--

INSERT INTO `accesso_prodotto` (`id_prodotto`, `username_staff`) VALUES
(5, 'staffstaff'),
(6, 'staff1'),
(7, 'staff1'),
(8, 'staff1');

-- --------------------------------------------------------

--
-- Struttura della tabella `centro_assistenza`
--

CREATE TABLE `centro_assistenza` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `nome` varchar(255) NOT NULL,
  `indirizzo` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `centro_assistenza`
--

INSERT INTO `centro_assistenza` (`id`, `nome`, `indirizzo`) VALUES
(1, 'Centro Assistenza Apple Roma', 'Via Roma 123, Roma'),
(2, 'Centro Assistenza Milano', 'Corso Milasno 45, Milano'),
(3, 'Centro Assistenza Napoli', 'Piazza Napoli 12, Napoli');

-- --------------------------------------------------------

--
-- Struttura della tabella `malfunzionamento`
--

CREATE TABLE `malfunzionamento` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `nome` varchar(255) NOT NULL,
  `descrizione` text NOT NULL,
  `nome_soluzione` text DEFAULT NULL,
  `descrizione_soluzione` text DEFAULT NULL,
  `id_prodotto` bigint(20) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `malfunzionamento`
--

INSERT INTO `malfunzionamento` (`id`, `nome`, `descrizione`, `nome_soluzione`, `descrizione_soluzione`, `id_prodotto`) VALUES
(8, 'Problema audio', 'Gli AirPods non riproducono l’audio o si disconnettono frequentemente.', 'Ripristino degli AirPods', 'Rimuovi gli AirPods dalle impostazioni Bluetooth e riconnettili.', 5),
(9, 'Mac lentoqq', 'Il Mac è lento o si blocca frequentemente.', 'a', 'a', 6),
(10, 'Nessuna risposta vocale', 'HomePod non risponde ai comandi vocali.', 'Riavvio di HomePod', 'Scollega l’alimentazione e ricollega il dispositivo dopo 10 secondi.', 7),
(11, 'Surriscaldamento', 'Il dispositivo si surriscalda durante l’uso intenso.', 'Ventilazione migliorata', 'Pulire le ventole o posizionare il dispositivo in un’area ben ventilata.', 8),
(12, 'Segnale Bluetooth assente', 'Il dispositivo non riesce a connettersi tramite Bluetooth.', 'Ripristino Bluetooth', 'Attiva/disattiva il Bluetooth o riavvia il dispositivo.', 10),
(13, 'Nessun segnale TV', 'Apple TV non trasmette segnale al televisore.', 'Verifica cavi HDMI', 'Controllare il cavo HDMI e riavviare Apple TV.', 9),
(14, 'Dispositivo non trovato', 'L’AirTag non viene rilevato nell’app Dov’è.', 'Ripristino AirTag', 'Rimuovi l’AirTag dall’account e riconnettilo.', 11),
(19, 'sono caa', 'prova scusa ciao', NULL, NULL, 5),
(20, 'a', 'ciao dell\'ipad', NULL, NULL, 5);

-- --------------------------------------------------------

--
-- Struttura della tabella `migrations`
--

CREATE TABLE `migrations` (
  `id` int(10) UNSIGNED NOT NULL,
  `migration` varchar(255) NOT NULL,
  `batch` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `migrations`
--

INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES
(121, '2019_12_14_000001_create_personal_access_tokens_table', 1),
(122, '2024_12_09_154630_prodotto', 1),
(123, '2024_12_09_155806_user', 1),
(124, '2024_12_09_155956_centro_assistenza', 1),
(125, '2024_12_09_160016_malfunzionamento', 1),
(126, '2024_12_09_161349_staff', 1),
(127, '2024_12_09_161411_tecnico', 1),
(128, '2024_12_09_163908_accesso_prodotto', 1);

-- --------------------------------------------------------

--
-- Struttura della tabella `personal_access_tokens`
--

CREATE TABLE `personal_access_tokens` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `tokenable_type` varchar(255) NOT NULL,
  `tokenable_id` bigint(20) UNSIGNED NOT NULL,
  `name` varchar(255) NOT NULL,
  `token` varchar(64) NOT NULL,
  `abilities` text DEFAULT NULL,
  `last_used_at` timestamp NULL DEFAULT NULL,
  `expires_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struttura della tabella `prodotto`
--

CREATE TABLE `prodotto` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `nome` varchar(255) NOT NULL,
  `descrizione` text NOT NULL,
  `note_tecniche` text NOT NULL,
  `modalita_installazione` text NOT NULL,
  `foto` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `prodotto`
--

INSERT INTO `prodotto` (`id`, `nome`, `descrizione`, `note_tecniche`, `modalita_installazione`, `foto`) VALUES
(5, 'AirPods Pro 2', 'Cuffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.', 'uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.Audio spaziale, Bluetooth 5.3, Ricarica MagSafe.', 'uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.uffie wireless con cancellazione attiva del rumore e modalità Trasparenza.Accoppia con l’iPhone tramite l’app Impostazioni > Bluetooth.', 'prova.png'),
(6, 'iMac 24\" M1', 'Desktop all-in-one con processore M1 e display Retina 4.5K.', 'Memoria: 8GB, Archiviazione: 256GB SSD, GPU 8-core.', 'Accendi e configura tramite macOS Setup Assistant.', 'prova.png'),
(7, 'HomePod Mini', 'Speaker intelligente con Siri e audio a 360 gradi.', 'Chip S5, Audio a 360°, Supporto per HomeKit.', 'Accoppia con l’iPhone tramite l’app Casa.', 'prova.png'),
(8, 'Mac Studio M1 Ultra', 'Computer desktop potente con chip M1 Ultra.', 'CPU 20-core, GPU 64-core, 128GB RAM.', 'Accendi e configura tramite macOS Setup Assistant.', 'prova.png'),
(9, 'Apple TV 4K', 'Dispositivo di streaming con supporto Dolby Vision e Dolby Atmos.', 'Chip A12 Bionic, HDR10, HDMI 2.1.', 'Collega alla TV tramite HDMI e configura con l’iPhone.', 'prova.png'),
(10, 'Magic Keyboard', 'Tastiera wireless retroilluminata con trackpad integrato.', 'Bluetooth, Ricarica USB-C.', 'Associa tramite Bluetooth nelle impostazioni.', 'prova.png'),
(11, 'AirTag', 'Dispositivo di localizzazione con chip U1 e integrazione con l’app Dov’è.', 'Chip U1, Bluetooth LE.', 'Accoppia con l’iPhone e personalizza il nome.', 'prova.png');

-- --------------------------------------------------------

--
-- Struttura della tabella `staff`
--

CREATE TABLE `staff` (
  `username` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `staff`
--

INSERT INTO `staff` (`username`) VALUES
('staff1'),
('staff2'),
('staffstaff');

-- --------------------------------------------------------

--
-- Struttura della tabella `tecnico`
--

CREATE TABLE `tecnico` (
  `username` varchar(255) NOT NULL,
  `dataDiNascita` date NOT NULL,
  `specializzazione` enum('Tecnico Certificato IOS','Tecnico Certificato Apple','Tecnico hardware','Tecnico software') NOT NULL,
  `id_centro_assistenza` bigint(20) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `tecnico`
--

INSERT INTO `tecnico` (`username`, `dataDiNascita`, `specializzazione`, `id_centro_assistenza`) VALUES
('tecnico1', '2025-02-05', 'Tecnico Certificato IOS', 2),
('tecnico44', '2000-01-01', 'Tecnico hardware', 3);

-- --------------------------------------------------------

--
-- Struttura della tabella `user`
--

CREATE TABLE `user` (
  `username` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `nome` varchar(255) NOT NULL,
  `cognome` varchar(255) NOT NULL,
  `role` varchar(9) NOT NULL DEFAULT 'staff',
  `remember_token` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dump dei dati per la tabella `user`
--

INSERT INTO `user` (`username`, `password`, `nome`, `cognome`, `role`, `remember_token`, `created_at`, `updated_at`) VALUES
('admin', '$2y$12$c3UJeFH11C/XsJljSATjZ.pijOqdoMhoMTrMcr3cWoqqQTrbCZU5S', 'Admin', 'Admin', 'admin', NULL, NULL, NULL),
('adminadmin', '$2y$12$QUP0eT6jSNUNNjnK6WV.I.ObRkoFf6G7sNNAySlY7y6mtAZLhRFTC', 'Admin', 'Admin', 'admin', NULL, NULL, NULL),
('staff1', '$2y$12$rQL/kSEY2mxL4zxlXdM.LO1HCKZgHjOF340MzsIOBkELkSLDKZkja', 'Mario', 'Rossi', 'staff', NULL, NULL, NULL),
('staff2', '$2y$12$uwfUL8YXcU9uP7o.f74RJ.jbHedFQwOSmd5sXldVtAMX6HypilZDW', 'Luca', 'Bianchi', 'staff', NULL, NULL, NULL),
('staffstaff', '$2y$12$.5riYu3peZq.B0ld/c5/2.AB0pnG.VFbKHL5J8CuqRdfBYYYWt2fG', 'Sara', 'Neri', 'staff', NULL, NULL, NULL),
('tecnico1', '$2y$12$.bM7riniUqteUks.AAjz7.7cZV6eQmi2w2bjMq6S9Y.yYdYThgdyW', 'a', 'a', 'tecnico', NULL, '2025-02-06 15:26:43', '2025-02-17 10:07:32'),
('tecnico44', '$2y$12$jvHo0Si0Rkd3gr4z7asPwudzdKPw2r9oGW6TaxeHZlT3j1nT8tRnq', 'Giulia', 'Verdi', 'tecnico', NULL, NULL, '2025-02-06 15:36:51');

--
-- Indici per le tabelle scaricate
--

--
-- Indici per le tabelle `accesso_prodotto`
--
ALTER TABLE `accesso_prodotto`
  ADD PRIMARY KEY (`id_prodotto`,`username_staff`),
  ADD KEY `accesso_prodotto_username_staff_foreign` (`username_staff`);

--
-- Indici per le tabelle `centro_assistenza`
--
ALTER TABLE `centro_assistenza`
  ADD PRIMARY KEY (`id`);

--
-- Indici per le tabelle `malfunzionamento`
--
ALTER TABLE `malfunzionamento`
  ADD PRIMARY KEY (`id`),
  ADD KEY `malfunzionamento_id_prodotto_foreign` (`id_prodotto`);

--
-- Indici per le tabelle `migrations`
--
ALTER TABLE `migrations`
  ADD PRIMARY KEY (`id`);

--
-- Indici per le tabelle `personal_access_tokens`
--
ALTER TABLE `personal_access_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `personal_access_tokens_token_unique` (`token`),
  ADD KEY `personal_access_tokens_tokenable_type_tokenable_id_index` (`tokenable_type`,`tokenable_id`);

--
-- Indici per le tabelle `prodotto`
--
ALTER TABLE `prodotto`
  ADD PRIMARY KEY (`id`);
ALTER TABLE `prodotto` ADD FULLTEXT KEY `descrizione` (`descrizione`);

--
-- Indici per le tabelle `staff`
--
ALTER TABLE `staff`
  ADD PRIMARY KEY (`username`);

--
-- Indici per le tabelle `tecnico`
--
ALTER TABLE `tecnico`
  ADD PRIMARY KEY (`username`),
  ADD KEY `tecnico_id_centro_assistenza_foreign` (`id_centro_assistenza`);

--
-- Indici per le tabelle `user`
--
ALTER TABLE `user`
  ADD PRIMARY KEY (`username`);

--
-- AUTO_INCREMENT per le tabelle scaricate
--

--
-- AUTO_INCREMENT per la tabella `centro_assistenza`
--
ALTER TABLE `centro_assistenza`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT per la tabella `malfunzionamento`
--
ALTER TABLE `malfunzionamento`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT per la tabella `migrations`
--
ALTER TABLE `migrations`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=129;

--
-- AUTO_INCREMENT per la tabella `personal_access_tokens`
--
ALTER TABLE `personal_access_tokens`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT per la tabella `prodotto`
--
ALTER TABLE `prodotto`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- Limiti per le tabelle scaricate
--

--
-- Limiti per la tabella `accesso_prodotto`
--
ALTER TABLE `accesso_prodotto`
  ADD CONSTRAINT `accesso_prodotto_id_prodotto_foreign` FOREIGN KEY (`id_prodotto`) REFERENCES `prodotto` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `accesso_prodotto_username_staff_foreign` FOREIGN KEY (`username_staff`) REFERENCES `staff` (`username`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Limiti per la tabella `malfunzionamento`
--
ALTER TABLE `malfunzionamento`
  ADD CONSTRAINT `malfunzionamento_id_prodotto_foreign` FOREIGN KEY (`id_prodotto`) REFERENCES `prodotto` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Limiti per la tabella `staff`
--
ALTER TABLE `staff`
  ADD CONSTRAINT `staff_username_foreign` FOREIGN KEY (`username`) REFERENCES `user` (`username`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Limiti per la tabella `tecnico`
--
ALTER TABLE `tecnico`
  ADD CONSTRAINT `tecnico_id_centro_assistenza_foreign` FOREIGN KEY (`id_centro_assistenza`) REFERENCES `centro_assistenza` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `tecnico_username_foreign` FOREIGN KEY (`username`) REFERENCES `user` (`username`) ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
