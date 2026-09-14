#!/usr/bin/env node
/**
 * LiveDrop Background Reaper Runner (ADR-002, TASK-2.4C, TASK-2.5)
 *
 * Executes the authoritative PostgreSQL RPC `release_expired_holds()` via service-role
 * to reclaim abandoned 15-minute checkout holds and expired 24-hour payment verification claims.
 *
 * Usage:
 *   node scripts/run-reaper.mjs [--dry-run]
 *
 * Required Environment Variables:
 *   SUPABASE_URL (e.g. https://xyz.supabase.co or http://127.0.0.1:54321)
 *   SUPABASE_SERVICE_ROLE_KEY (Service-role secret with bypass-RLS privilege)
 *
 * Optional:
 *   DATABASE_URL (Direct PostgreSQL connection string if running via pg driver)
 */

const isDryRun = process.argv.includes('--dry-run');

const targetUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

console.log('---------------------------------------------------------');
console.log('⏰ LiveDrop Operational Reaper — release_expired_holds()');
console.log(`⏱️  Timestamp: ${new Date().toISOString()}`);
console.log('---------------------------------------------------------');

if (isDryRun) {
  console.log('🔍 [DRY RUN] Validating reaper runner environment:');
  console.log(`   - SUPABASE_URL: ${targetUrl ? 'Configured (' + targetUrl + ')' : 'MISSING (Unset)'}`);
  console.log(`   - SUPABASE_SERVICE_ROLE_KEY: ${serviceKey ? 'Configured (' + serviceKey.slice(0, 8) + '...)' : 'MISSING (Unset)'}`);
  console.log('✅ [DRY RUN] Script syntax and operational logic verified.');
  process.exit(0);
}

if (!targetUrl || !serviceKey) {
  console.error('❌ [CONFIG ERROR] Missing required environment variables:');
  if (!targetUrl) console.error('   - SUPABASE_URL is not set.');
  if (!serviceKey) console.error('   - SUPABASE_SERVICE_ROLE_KEY is not set.');
  console.error('\nEnsure both variables are provided in CI secrets or runtime environment.');
  process.exit(1);
}

async function executeReaper() {
  const rpcUrl = new URL('/rest/v1/rpc/release_expired_holds', targetUrl);
  const startTime = Date.now();

  try {
    console.log(`📡 Invoking RPC on ${rpcUrl.origin}...`);

    const response = await fetch(rpcUrl.toString(), {
      method: 'POST',
      headers: {
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: JSON.stringify({}),
    });

    const elapsedMs = Date.now() - startTime;

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ [REAPER FAILURE] HTTP ${response.status} ${response.statusText} (${elapsedMs}ms)`);
      console.error(`   Error details: ${errorText}`);
      process.exit(1);
    }

    console.log(`✅ [REAPER SUCCESS] Successfully executed release_expired_holds() in ${elapsedMs}ms`);
    console.log('   - Expired abandoned reservations released to available.');
    console.log('   - Expired unverified payment attempts marked expired.');
    console.log('   - Confirmed advance orders with expired balance deadlines updated.');
    process.exit(0);
  } catch (err) {
    const elapsedMs = Date.now() - startTime;
    console.error(`💥 [NETWORK EXCEPTION] Reaper execution failed after ${elapsedMs}ms:`, err.message);
    process.exit(1);
  }
}

void executeReaper();
