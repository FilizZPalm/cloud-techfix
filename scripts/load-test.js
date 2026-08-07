/**
 * k6 Load Test — TechFix Product Recall Scenario
 *
 * Simula 200 utenti concorrenti che navigano il catalogo prodotti,
 * come avviene durante un product recall.
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

// Metriche custom
const catalogoErrors = new Rate('catalogo_errors');
const catalogoPageErrors = new Rate('catalogo_page_errors');
const catalogoDuration = new Trend('catalogo_duration', true);
const catalogoPageDuration = new Trend('catalogo_page_duration', true);

export const options = {
  vus: 200,
  duration: '3m',
  
  //tlsConfig: {
  insecureSkipVerify: true,
  //},
  thresholds: {
    http_req_failed: ['rate<0.05'],         // < 5% richieste fallite
    http_req_duration: ['p(95)<5000'],      // p95 latenza < 5 secondi
  },
};

const BASE_URL = 'https://techfix.local';

export default function () {
  // Scenario 1: GET homepage (pagina principale con catalogo)
  const homeRes = http.get(`${BASE_URL}/`, {
    tags: { name: 'homepage' },
  });

  check(homeRes, {
    'homepage: status 200': (r) => r.status === 200,
    'homepage: body non vuoto': (r) => r.body && r.body.length > 0,
  });

  catalogoErrors.add(homeRes.status !== 200);
  catalogoDuration.add(homeRes.timings.duration);

  sleep(0.5);

  // Scenario 2: GET pagina catalogo (lista prodotti)
  const catalogoRes = http.get(`${BASE_URL}/catalogo`, {
    tags: { name: 'catalogo' },
  });

  check(catalogoRes, {
    'catalogo: status 200': (r) => r.status === 200,
    'catalogo: body contiene prodotti': (r) => r.body && r.body.length > 100,
  });

  catalogoPageErrors.add(catalogoRes.status !== 200);
  catalogoPageDuration.add(catalogoRes.timings.duration);

  // Pausa tra iterazioni (simula think time utente: 0.5-1.5 secondi)
  sleep(Math.random() * 1 + 0.5);
}
