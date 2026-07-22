/**
 * k6 Load Test — TechFix Product Recall Scenario
 *
 * Simula 50 utenti concorrenti che navigano il catalogo prodotti e cercano
 * malfunzionamenti, come avviene durante un product recall.
 *
 * Requisiti validati:
 * - Requirement 12.1: Load generator con almeno 50 VU, durata minima 3 minuti
 * - Requirement 12.4: Tasso di successo ≥ 95%, latenza p95 < 5 secondi
 *
 * Esecuzione:
 *   k6 run scripts/load-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Metriche custom per tracciare separatamente catalogo e ricerca
const catalogoErrors = new Rate('catalogo_errors');
const ricercaErrors = new Rate('ricerca_errors');
const catalogoDuration = new Trend('catalogo_duration', true);
const ricercaDuration = new Trend('ricerca_duration', true);

export const options = {
  vus: 200,
  duration: '3m',
  insecureSkipTLSVerify: true,
  thresholds: {
    http_req_failed: ['rate<0.05'],         // < 5% richieste fallite
    http_req_duration: ['p(95)<5000'],      // p95 latenza < 5 secondi
  },
};

const BASE_URL = 'https://techfix.local';

// Termini di ricerca realistici per simulare ricerche malfunzionamenti
const searchTerms = [
  'schermo',
  'batteria',
  'audio',
  'wifi',
  'bluetooth',
  'riavvio',
  'surriscaldamento',
  'fotocamera',
  'memoria',
  'aggiornamento',
];

export default function () {
  // Scenario 1: GET catalogo prodotti (pagina principale)
  const catalogoRes = http.get(`${BASE_URL}/`, {
    tags: { name: 'catalogo' },
  });

  check(catalogoRes, {
    'catalogo: status 200': (r) => r.status === 200,
    'catalogo: body non vuoto': (r) => r.body && r.body.length > 0,
  });

  catalogoErrors.add(catalogoRes.status !== 200);
  catalogoDuration.add(catalogoRes.timings.duration);

  sleep(1);

  // Scenario 2: GET ricerca AJAX prodotti (simula ricerca utente nel catalogo)
  const term = searchTerms[Math.floor(Math.random() * searchTerms.length)];
  const ricercaRes = http.get(`${BASE_URL}/catalogo/filtra?search=${term}`, {
    tags: { name: 'ricerca_malfunzionamenti' },
    headers: {
      'X-Requested-With': 'XMLHttpRequest',
      'Accept': 'application/json',
    },
  });

  check(ricercaRes, {
    'ricerca: status 200 o 302': (r) => r.status === 200 || r.status === 302,
    'ricerca: risposta ricevuta': (r) => r.body !== null,
  });

  ricercaErrors.add(ricercaRes.status !== 200 && ricercaRes.status !== 302);
  ricercaDuration.add(ricercaRes.timings.duration);

  // Pausa tra iterazioni (simula think time utente: 0.5-1.5 secondi)
  sleep(Math.random() * 1 + 0.5);
}
