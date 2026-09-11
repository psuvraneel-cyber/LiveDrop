#!/usr/bin/env node
/**
 * LiveDrop Free-Tier Inactivity Keepalive Probe (ADR-008)
 * Performs a lightweight health check ping against the Supabase REST endpoint.
 */

const https = require('https');
const http = require('http');

const targetUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;

if (!targetUrl) {
  console.log('No SUPABASE_URL configured. Skipping keepalive ping in local/dev environment.');
  process.exit(0);
}

try {
  const url = new URL('/rest/v1/', targetUrl);
  const client = url.protocol === 'https:' ? https : http;

  console.log(`[Keepalive] Pinging ${url.origin}...`);
  const req = client.get(url, (res) => {
    console.log(`[Keepalive] Received HTTP ${res.statusCode}`);
    process.exit(0);
  });

  req.on('error', (err) => {
    console.error(`[Keepalive Error] ${err.message}`);
    // Non-fatal exit so CI workflows don't fail if project is temporarily offline
    process.exit(0);
  });
} catch (err) {
  console.error(`[Keepalive Invalid URL] ${err.message}`);
  process.exit(0);
}
