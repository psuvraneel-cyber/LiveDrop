/**
 * LiveDrop — Local Development Supabase Mock Gateway
 *
 * Provides local HTTP REST (PostgREST) and WebSocket (Realtime) emulation
 * matching seed data for end-to-end browser validation of TASK-2.1.
 */

import http from 'http';
import crypto from 'crypto';

const PORT = 54321;

// Seed data
const mockProfile = {
  store_name: "Mother's Boutique",
  phone_number: '919830012345',
  upi_id: 'mothersboutique@okaxis',
  upi_qr_url: 'https://storage.livedrop.store/qrs/mb.webp',
  default_shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
};

const mockLiveDrop = {
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
  seller_id: '8a329e71-4b10-4055-90d2-df8029d5b512',
  title: 'Friday Silk Special',
  slug: 'mothers-boutique',
  status: 'live',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  live_started_at: '2026-09-11T13:00:00Z',
  closed_at: null,
  created_at: '2026-09-11T12:00:00Z',
  updated_at: '2026-09-11T12:00:00Z',
  profiles: mockProfile,
};

const mockEmptyDrop = {
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6809',
  seller_id: '8a329e71-4b10-4055-90d2-df8029d5b512',
  title: 'Empty Live Drop',
  slug: 'empty-drop',
  status: 'live',
  shipping_fee_paisa: 5000,
  free_shipping_threshold_paisa: null,
  live_started_at: '2026-09-11T14:00:00Z',
  closed_at: null,
  created_at: '2026-09-11T14:00:00Z',
  updated_at: '2026-09-11T14:00:00Z',
  profiles: {
    store_name: "Artisan Silks",
    phone_number: '919830099999',
    upi_id: 'artisansilks@upi',
    upi_qr_url: null,
    default_shipping_fee_paisa: 5000,
    free_shipping_threshold_paisa: null,
  },
};

const mockClosedDrop = {
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6802',
  seller_id: '8a329e71-4b10-4055-90d2-df8029d5b512',
  title: 'Past Clearance Collection',
  slug: 'past-clearance',
  status: 'closed',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  live_started_at: '2026-09-10T10:00:00Z',
  closed_at: '2026-09-10T14:00:00Z',
  created_at: '2026-09-10T09:00:00Z',
  updated_at: '2026-09-10T14:00:00Z',
  profiles: mockProfile,
};

let products = [
  {
    id: 'e9314c99-7f55-4089-a2bb-b001d2950df1',
    code: '#A01',
    title: 'Handloom Tussar Saree',
    price_paisa: 185000,
    size: 'Free Size',
    image_url: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?w=400&q=80',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'a8219c11-1b22-4899-b1cc-c112d2950de2',
    code: '#A02',
    title: 'Chanderi Cotton Kurti',
    price_paisa: 75000,
    size: 'L',
    image_url: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?w=400&q=80',
    status: 'reserved',
    reserved_at: '2026-09-11T14:30:00Z',
    version: 2,
  },
  {
    id: 'f7105d88-3c44-4177-90aa-e221d2950da3',
    code: '#A03',
    title: 'Pure Jamdani Silk Dupatta',
    price_paisa: 125000,
    size: 'Free Size',
    image_url: 'https://images.unsplash.com/photo-1617627143750-d86bc21e42bb?w=400&q=80',
    status: 'sold',
    reserved_at: null,
    version: 3,
  },
  {
    id: 'b4567d11-2c33-4988-a2dd-e331d2950df4',
    code: '#A04',
    title: 'Artisan Pashmina Shawl (Broken Image)',
    price_paisa: 95000,
    size: 'Free Size',
    image_url: 'https://invalid-broken-domain-999.test/broken-image.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
];

const connectedClients = new Set();

function buildWebSocketFrame(payloadStr) {
  const payloadBuffer = Buffer.from(payloadStr);
  const length = payloadBuffer.length;

  let header;
  if (length <= 125) {
    header = Buffer.alloc(2);
    header[0] = 0x81; // FIN + text opcode
    header[1] = length;
  } else if (length <= 65535) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }

  return Buffer.concat([header, payloadBuffer]);
}

function parseWebSocketFrame(buffer) {
  if (buffer.length < 2) return null;
  const isMasked = (buffer[1] & 0x80) === 0x80;
  let length = buffer[1] & 0x7f;
  let offset = 2;

  if (length === 126) {
    length = buffer.readUInt16BE(2);
    offset = 4;
  } else if (length === 127) {
    length = Number(buffer.readBigUInt64BE(2));
    offset = 10;
  }

  let maskKey = null;
  if (isMasked) {
    maskKey = buffer.slice(offset, offset + 4);
    offset += 4;
  }

  const payload = buffer.slice(offset, offset + length);
  if (isMasked && maskKey) {
    for (let i = 0; i < payload.length; i++) {
      payload[i] ^= maskKey[i % 4];
    }
  }

  return payload.toString('utf8');
}

const server = http.createServer((req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  // POST /broadcast-update (trigger realtime event)
  if (req.method === 'POST' && pathname === '/broadcast-update') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body);
        const updatedProduct = payload.product;

        // Update local product cache
        const index = products.findIndex(p => p.id === updatedProduct.id);
        if (index >= 0) {
          products[index] = { ...products[index], ...updatedProduct };
        } else {
          products.push(updatedProduct);
        }

        const dropId = payload.dropId || mockLiveDrop.id;
        const topic = `realtime:drop:${dropId}:products`;

        const message = JSON.stringify({
          topic,
          event: 'postgres_changes',
          payload: {
            data: {
              schema: 'public',
              table: 'products',
              commit_timestamp: new Date().toISOString(),
              eventType: 'UPDATE',
              new: updatedProduct,
              old: { id: updatedProduct.id },
            },
          },
          ref: null,
        });

        const frame = buildWebSocketFrame(message);
        for (const client of connectedClients) {
          client.write(frame);
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, clientsNotified: connectedClients.size }));
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // GET /rest/v1/drops
  if (pathname === '/rest/v1/drops') {
    const slug = parsedUrl.searchParams.get('slug');
    const status = parsedUrl.searchParams.get('status');

    let matchedDrop = null;
    if (slug === 'eq.mothers-boutique' && status === 'eq.live') {
      matchedDrop = mockLiveDrop;
    } else if (slug === 'eq.empty-drop' && status === 'eq.live') {
      matchedDrop = mockEmptyDrop;
    }

    const acceptHeader = req.headers['accept'] || '';
    if (acceptHeader.includes('application/vnd.pgrst.object+json')) {
      if (matchedDrop) {
        res.writeHead(200, { 'Content-Type': 'application/vnd.pgrst.object+json' });
        res.end(JSON.stringify(matchedDrop));
      } else {
        res.writeHead(406, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ message: 'JSON object requested, multiple (or no) rows returned' }));
      }
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(matchedDrop ? [matchedDrop] : []));
    }
    return;
  }

  // GET /rest/v1/products
  if (pathname === '/rest/v1/products') {
    const dropId = parsedUrl.searchParams.get('drop_id');

    if (dropId === `eq.${mockLiveDrop.id}`) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(products));
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify([]));
    }
    return;
  }

  // Health check / fallback
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'ok', service: 'livedrop-dev-mock-supabase' }));
});

// Handle WebSocket upgrade for Supabase Realtime
server.on('upgrade', (req, socket, head) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) {
    socket.destroy();
    return;
  }

  const acceptKey = crypto
    .createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');

  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`
  );

  connectedClients.add(socket);

  socket.on('data', buffer => {
    try {
      const text = parseWebSocketFrame(buffer);
      if (!text) return;

      const parsed = JSON.parse(text);
      const { topic, event, ref, join_ref } = parsed;

      // Reply to phx_join
      if (event === 'phx_join') {
        const reply = JSON.stringify({
          topic,
          event: 'phx_reply',
          payload: { response: { postgres_changes: [] }, status: 'ok' },
          ref,
          join_ref,
        });
        socket.write(buildWebSocketFrame(reply));
      } else if (event === 'heartbeat') {
        const reply = JSON.stringify({
          topic: 'phoenix',
          event: 'phx_reply',
          payload: { response: {}, status: 'ok' },
          ref,
        });
        socket.write(buildWebSocketFrame(reply));
      }
    } catch {
      // Ignore unparseable frames
    }
  });

  socket.on('close', () => {
    connectedClients.delete(socket);
  });

  socket.on('error', () => {
    connectedClients.delete(socket);
  });
});

server.listen(PORT, () => {
  console.log(`[DevMockSupabase] Running on http://127.0.0.1:${PORT}`);
});
