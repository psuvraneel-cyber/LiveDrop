#!/usr/bin/env node
/**
 * LiveDrop Free-Tier Inactivity Keepalive Probe (ADR-008)
 * Performs a lightweight health check ping against the Supabase REST endpoint.
 *
 * Exit codes: 0 = project responded (any HTTP status < 500),
 *             1 = unreachable, timed out, 5xx, invalid URL, or URL missing in CI.
 */

const https = require('https');
const http = require('http');

const TIMEOUT_MS = 15000;
const targetUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;

if (!targetUrl) {
  if (process.env.CI) {
    console.error('[Keepalive Error] No SUPABASE_URL configured in CI. Set the SUPABASE_URL repository secret.');
    process.exit(1);
  }
  console.log('No SUPABASE_URL configured. Skipping keepalive ping in local/dev environment.');
  process.exit(0);
}

let url;
try {
  url = new URL('/rest/v1/', targetUrl);
} catch (err) {
  console.error(`[Keepalive Invalid URL] ${err.message}`);
  process.exit(1);
}

const client = url.protocol === 'https:' ? https : http;
console.log(`[Keepalive] Pinging ${url.origin}...`);

const req = client.get(url, { timeout: TIMEOUT_MS }, (res) => {
  console.log(`[Keepalive] Received HTTP ${res.statusCode}`);
  res.resume();
  if (res.statusCode >= 500) {
    console.error(`[Keepalive Error] Server error HTTP ${res.statusCode}.`);
    process.exit(1);
  }
  process.exit(0);
});

req.on('timeout', () => {
  req.destroy(new Error(`Request timed out after ${TIMEOUT_MS}ms`));
});

req.on('error', (err) => {
  console.error(`[Keepalive Error] ${err.message}`);
  process.exit(1);
});
