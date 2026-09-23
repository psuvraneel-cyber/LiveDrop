/**
 * LiveDrop — Automated Multi-Role E2E Test Suite Orchestrator (Sprint 4 / Phase 10)
 *
 * Spawns the local Supabase Mock Gateway (Port 54321) and Next.js Buyer Web Server (Port 3000),
 * executes the complete Playwright E2E test suite, and ensures clean process teardown.
 */

import { spawn } from 'child_process';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const buyerWebDir = path.resolve(rootDir, 'buyer-web');

function waitForHttp(url, timeoutMs = 30000) {
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      http
        .get(url, (res) => {
          if (res.statusCode && res.statusCode < 500) {
            resolve();
          } else {
            retry();
          }
        })
        .on('error', () => {
          retry();
        });
    };

    const retry = () => {
      if (Date.now() - startTime > timeoutMs) {
        reject(new Error(`Timeout waiting for ${url} after ${timeoutMs}ms`));
      } else {
        setTimeout(check, 500);
      }
    };

    check();
  });
}

async function run() {
  console.log('================================================================');
  console.log('🚀 LiveDrop Phase 10: Multi-Role Playwright E2E Test Runner');
  console.log('================================================================');

  const envLocal = path.resolve(buyerWebDir, '.env.local');
  const envLocalTmp = path.resolve(buyerWebDir, '.env.local.e2etmp');
  let renamedEnv = false;
  let mockServerProcess = null;
  let nextServerProcess = null;

  const cleanup = () => {
    console.log('\n🧹 Cleaning up test servers...');
    if (mockServerProcess) {
      mockServerProcess.kill();
      mockServerProcess = null;
    }
    if (nextServerProcess) {
      nextServerProcess.kill();
      nextServerProcess = null;
    }
    if (renamedEnv && fs.existsSync(envLocalTmp)) {
      try {
        fs.renameSync(envLocalTmp, envLocal);
        renamedEnv = false;
        console.log('  ✓ Restored .env.local');
      } catch (e) {
        console.error('Failed to restore .env.local:', e);
      }
    }
  };

  process.on('SIGINT', () => {
    cleanup();
    process.exit(1);
  });
  process.on('SIGTERM', () => {
    cleanup();
    process.exit(1);
  });

  try {
    if (fs.existsSync(envLocal)) {
      fs.renameSync(envLocal, envLocalTmp);
      renamedEnv = true;
      console.log('📦 Isolated .env.local for local mock E2E testing.');
    }

    // 1. Start Dev Mock Supabase Gateway
    console.log('📦 [1/3] Launching Supabase Mock Gateway on http://127.0.0.1:54321 ...');
    mockServerProcess = spawn('node', ['scripts/dev-mock-supabase.mjs'], {
      cwd: rootDir,
      stdio: 'pipe',
      env: { ...process.env, PORT: '54321' },
      shell: true,
    });

    mockServerProcess.stdout.on('data', (d) => {
      const msg = d.toString().trim();
      if (msg) console.log(`[MockGateway] ${msg}`);
    });

    mockServerProcess.stderr.on('data', (d) => {
      const msg = d.toString().trim();
      if (msg) console.error(`[MockGateway Error] ${msg}`);
    });

    await waitForHttp('http://127.0.0.1:54321');
    console.log('  ✓ Supabase Mock Gateway is ready.');

    // 2. Start Next.js Buyer Web Server
    console.log('🌐 [2/3] Launching Next.js Buyer Web on http://127.0.0.1:3000 ...');
    nextServerProcess = spawn('npx', ['next', 'dev', '-p', '3000'], {
      cwd: buyerWebDir,
      stdio: 'pipe',
      env: {
        ...process.env,
        PORT: '3000',
        NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
        NEXT_PUBLIC_SUPABASE_ANON_KEY: 'test-anon-key',
        NEXT_PUBLIC_APP_ENV: 'development',
      },
      shell: true,
    });

    nextServerProcess.stdout.on('data', (d) => {
      const msg = d.toString().trim();
      if (msg) console.log(`[NextJS] ${msg}`);
    });

    nextServerProcess.stderr.on('data', (d) => {
      const msg = d.toString().trim();
      if (msg && !msg.includes('ExperimentalWarning')) {
        console.error(`[NextJS Error] ${msg}`);
      }
    });

    await waitForHttp('http://127.0.0.1:3000', 35000);
    console.log('  ✓ Next.js Buyer Web server is ready.');

    // 3. Run Playwright E2E Tests
    console.log('🎭 [3/3] Executing Playwright End-to-End Test Suite ...');
    const playwrightProcess = spawn('npx', ['playwright', 'test', '--reporter=list'], {
      cwd: buyerWebDir,
      stdio: 'inherit',
      shell: true,
    });

    const exitCode = await new Promise((resolve) => {
      playwrightProcess.on('close', (code) => {
        resolve(code ?? 0);
      });
    });

    cleanup();

    if (exitCode === 0) {
      console.log('================================================================');
      console.log('✅ ALL MULTI-ROLE PLAYWRIGHT E2E LIFECYCLE TESTS PASSED!');
      console.log('================================================================');
      process.exit(0);
    } else {
      console.error(`❌ Playwright test run failed with exit code ${exitCode}`);
      process.exit(exitCode);
    }
  } catch (err) {
    cleanup();
    console.error(`❌ E2E Orchestration failed: ${err.message}`);
    process.exit(1);
  }
}

run();
