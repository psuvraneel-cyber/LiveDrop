/**
 * LiveDrop — Local Development Supabase Mock Gateway
 *
 * Provides local HTTP REST (PostgREST), RPC execution, and WebSocket (Realtime) emulation
 * matching seed data for end-to-end browser validation and multi-role testing.
 */

import http from 'http';
import crypto from 'crypto';

const PORT = 54321;

// Initial state template
const initialProfile = {
  id: '8a329e71-4b10-4055-90d2-df8029d5b512',
  store_name: "Mother's Boutique",
  store_slug: 'mothers-boutique',
  phone_number: '919830012345',
  upi_id: 'mothersboutique@okaxis',
  upi_vpa: 'mothersboutique@okaxis',
  upi_display_name: "Mother's Boutique",
  upi_enabled: true,
  upi_qr_url: 'https://storage.livedrop.store/qrs/mb.webp',
  default_shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  advance_confirmation_enabled: true,
  advance_amount_paisa: 25000,
  hold_duration_days: 30,
};

const initialLiveDrop = {
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
  seller_id: '8a329e71-4b10-4055-90d2-df8029d5b512',
  title: 'Friday Silk Special',
  slug: 'mothers-boutique',
  status: 'live',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  advance_confirmation_enabled: null,
  advance_amount_paisa: null,
  hold_duration_days: null,
  live_started_at: '2026-09-11T13:00:00Z',
  closed_at: null,
  created_at: '2026-09-11T12:00:00Z',
  updated_at: '2026-09-11T12:00:00Z',
  profiles: initialProfile,
};

const initialProducts = [
  {
    id: 'e9314c99-7f55-4089-a2bb-b001d2950df1',
    drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
    code: '#A01',
    title: 'Handloom Tussar Saree',
    price_paisa: 149900,
    size: 'Free Size',
    image_url: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?w=400&q=80',
    status: 'available',
    reserved_at: null,
    reserved_by_order_id: null,
    version: 1,
  },
  {
    id: 'a8219c11-1b22-4899-b1cc-c112d2950de2',
    drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
    code: '#A02',
    title: 'Chanderi Cotton Kurti',
    price_paisa: 75000,
    size: 'L',
    image_url: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?w=400&q=80',
    status: 'reserved',
    reserved_at: '2026-09-11T14:30:00Z',
    reserved_by_order_id: null,
    version: 2,
  },
  {
    id: 'f7105d88-3c44-4177-90aa-e221d2950da3',
    drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
    code: '#A03',
    title: 'Pure Jamdani Silk Dupatta',
    price_paisa: 125000,
    size: 'Free Size',
    image_url: 'https://images.unsplash.com/photo-1617627143750-d86bc21e42bb?w=400&q=80',
    status: 'sold',
    reserved_at: null,
    reserved_by_order_id: null,
    version: 3,
  },
];

let mockProfile = JSON.parse(JSON.stringify(initialProfile));
let mockDrops = [JSON.parse(JSON.stringify(initialLiveDrop))];
let mockProducts = JSON.parse(JSON.stringify(initialProducts));
let mockOrders = [];
let mockPaymentAttempts = [];

const connectedClients = new Set();

function resetState() {
  mockProfile = JSON.parse(JSON.stringify(initialProfile));
  mockDrops = [JSON.parse(JSON.stringify(initialLiveDrop))];
  mockProducts = JSON.parse(JSON.stringify(initialProducts));
  mockOrders = [];
  mockPaymentAttempts = [];
}

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

function broadcastEvent(topic, table, eventType, record) {
  const message = JSON.stringify({
    topic,
    event: 'postgres_changes',
    payload: {
      data: {
        schema: 'public',
        table,
        commit_timestamp: new Date().toISOString(),
        eventType,
        new: record,
        old: { id: record.id },
      },
    },
    ref: null,
  });

  const frame = buildWebSocketFrame(message);
  for (const client of connectedClients) {
    try {
      client.write(frame);
    } catch {
      // Ignored
    }
  }
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

  // POST /reset-state
  if (req.method === 'POST' && pathname === '/reset-state') {
    resetState();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, message: 'State reset to seed default.' }));
    return;
  }

  // GET /rest/v1/drops or /rest/v1/public_seller_storefronts
  if (pathname === '/rest/v1/drops' || pathname === '/rest/v1/public_seller_storefronts') {
    const slug = parsedUrl.searchParams.get('slug');
    const status = parsedUrl.searchParams.get('status');

    let cleanSlug = slug ? slug.replace(/^eq\./, '') : null;
    let cleanStatus = status ? status.replace(/^eq\./, '') : null;

    let matchedDrop = mockDrops.find((d) => {
      if (cleanSlug && d.slug !== cleanSlug) return false;
      if (cleanStatus && d.status !== cleanStatus) return false;
      return true;
    });

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

  // GET /rest/v1/products or /rest/v1/public_products_catalog
  if (pathname === '/rest/v1/products' || pathname === '/rest/v1/public_products_catalog') {
    const dropIdParam = parsedUrl.searchParams.get('drop_id');
    const cleanDropId = dropIdParam ? dropIdParam.replace(/^eq\./, '') : null;

    const filtered = cleanDropId
      ? mockProducts.filter((p) => p.drop_id === cleanDropId)
      : mockProducts;

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(filtered));
    return;
  }

  // POST /rest/v1/rpc/create_order_with_reservation
  if (req.method === 'POST' && pathname === '/rest/v1/rpc/create_order_with_reservation') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const {
          p_drop_id,
          p_product_ids,
          p_buyer_name,
          p_buyer_phone,
          p_shipping_address,
          p_pincode,
          p_confirmation_mode,
          p_idempotency_key,
        } = payload;

        // Check Idempotency Key
        const cleanIdempotency = (p_idempotency_key || '').trim();
        if (cleanIdempotency) {
          const existing = mockOrders.find(
            (o) => o.drop_id === p_drop_id && o.idempotency_key === cleanIdempotency
          );
          if (existing) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(
              JSON.stringify({
                success: true,
                order_id: existing.id,
                order_code: existing.order_code,
                order_token: existing.order_token,
                subtotal_paisa: existing.subtotal_paisa,
                shipping_paisa: existing.shipping_paisa,
                total_paisa: existing.total_paisa,
                confirmation_mode: existing.confirmation_mode,
                advance_required_paisa: existing.advance_required_paisa,
                advance_paid_paisa: existing.advance_paid_paisa,
                balance_due_paisa: existing.balance_due_paisa,
                total_paid_paisa: existing.total_paid_paisa,
                payment_status: existing.payment_status,
                fulfilment_status: existing.fulfilment_status,
                hold_expires_at: existing.hold_expires_at,
                idempotent_replay: true,
              })
            );
            return;
          }
        }

        const cleanName = (p_buyer_name || '').trim();
        const cleanPhone = (p_buyer_phone || '').trim();
        const cleanAddress = (p_shipping_address || '').trim();
        const cleanPincode = (p_pincode || '').trim();
        const confirmationMode = (p_confirmation_mode || 'advance').toLowerCase().trim();

        if (cleanName.length < 3 || cleanName.length > 100) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              success: false,
              error: 'INVALID_BUYER_NAME',
              message: 'Buyer name must be between 3 and 100 characters.',
            })
          );
          return;
        }

        if (!(/^[6-9]\d{9}$/.test(cleanPhone) || /^91[6-9]\d{9}$/.test(cleanPhone))) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              success: false,
              error: 'INVALID_BUYER_PHONE',
              message: 'Valid 10-digit Indian mobile number required.',
            })
          );
          return;
        }

        if (cleanAddress.length < 10 || cleanAddress.length > 500) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              success: false,
              error: 'INVALID_SHIPPING_ADDRESS',
              message: 'Shipping address must be between 10 and 500 characters.',
            })
          );
          return;
        }

        if (!/^\d{6}$/.test(cleanPincode)) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              success: false,
              error: 'INVALID_PINCODE',
              message: 'Valid 6-digit Indian pincode required.',
            })
          );
          return;
        }

        const cleanIds = Array.from(new Set((p_product_ids || []).filter(Boolean)));
        if (cleanIds.length === 0) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'EMPTY_CART' }));
          return;
        }

        // Check product availability
        const unavailableIds = [];
        const matchedProducts = [];

        for (const id of cleanIds) {
          const prod = mockProducts.find((p) => p.id === id);
          if (!prod || prod.status !== 'available') {
            unavailableIds.push(id);
          } else {
            matchedProducts.push(prod);
          }
        }

        if (unavailableIds.length > 0) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              success: false,
              error: 'STOCK_UNAVAILABLE',
              unavailable_product_ids: unavailableIds,
              message: 'One or more items in your cart have already been reserved or sold.',
            })
          );
          return;
        }

        // Authoritative Subtotal & Shipping calculation in Paisa
        const subtotalPaisa = matchedProducts.reduce((sum, p) => sum + p.price_paisa, 0);
        const shippingPaisa = subtotalPaisa >= mockProfile.free_shipping_threshold_paisa ? 0 : mockProfile.default_shipping_fee_paisa;
        const totalPaisa = subtotalPaisa + shippingPaisa;

        let advanceRequiredPaisa = 0;
        let holdExpiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
        if (confirmationMode === 'advance') {
          advanceRequiredPaisa = mockProfile.advance_amount_paisa || 25000;
        } else {
          advanceRequiredPaisa = 0;
        }

        const orderCode = 'LD-' + crypto.randomBytes(3).toString('hex').toUpperCase();
        const orderId = crypto.randomUUID();
        const orderToken = crypto.randomUUID();

        // Mark products reserved and broadcast realtime update
        for (const prod of matchedProducts) {
          prod.status = 'reserved';
          prod.reserved_at = new Date().toISOString();
          prod.reserved_by_order_id = orderId;
          prod.version = (prod.version || 1) + 1;

          broadcastEvent(`realtime:drop:${p_drop_id}:products`, 'products', 'UPDATE', prod);
        }

        const newOrder = {
          id: orderId,
          drop_id: p_drop_id,
          order_code: orderCode,
          order_token: orderToken,
          idempotency_key: cleanIdempotency || null,
          buyer_name: cleanName,
          buyer_phone: cleanPhone,
          shipping_address: cleanAddress,
          pincode: cleanPincode,
          subtotal_paisa: subtotalPaisa,
          shipping_paisa: shippingPaisa,
          total_paisa: totalPaisa,
          confirmation_mode: confirmationMode,
          advance_required_paisa: advanceRequiredPaisa,
          advance_paid_paisa: 0,
          total_paid_paisa: 0,
          balance_due_paisa: totalPaisa,
          payment_status: 'unpaid',
          fulfilment_status: 'not_ready',
          status: 'pending',
          hold_expires_at: holdExpiresAt,
          store_name: mockProfile.store_name,
          store_slug: mockProfile.store_slug,
          upi_id: mockProfile.upi_id,
          upi_qr_url: mockProfile.upi_qr_url,
          tracking_number: null,
          courier_partner: null,
          shipped_at: null,
          notes: null,
          items: matchedProducts.map((p) => ({
            product_id: p.id,
            code: p.code,
            title: p.title,
            image_url: p.image_url,
            price_at_purchase_paisa: p.price_paisa,
          })),
        };
        mockOrders.push(newOrder);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            success: true,
            order_id: orderId,
            order_code: orderCode,
            order_token: orderToken,
            subtotal_paisa: subtotalPaisa,
            shipping_paisa: shippingPaisa,
            total_paisa: totalPaisa,
            confirmation_mode: confirmationMode,
            advance_required_paisa: advanceRequiredPaisa,
            advance_paid_paisa: 0,
            balance_due_paisa: totalPaisa,
            total_paid_paisa: 0,
            payment_status: 'unpaid',
            fulfilment_status: 'not_ready',
            hold_expires_at: holdExpiresAt,
          })
        );
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // POST /rest/v1/rpc/get_order_by_token
  if (req.method === 'POST' && pathname === '/rest/v1/rpc/get_order_by_token') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { p_order_id, p_order_token } = payload;
        const matched = mockOrders.find(
          (o) =>
            (p_order_id ? o.id === p_order_id : true) &&
            o.order_token === (p_order_token || payload.order_token)
        );

        if (!matched) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'ORDER_NOT_FOUND_OR_UNAUTHORIZED' }));
          return;
        }

        const activeAttempt = mockPaymentAttempts
          .filter((a) => a.order_id === matched.id)
          .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())[0] || null;

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            success: true,
            order: {
              ...matched,
              active_payment_attempt: activeAttempt,
              payment_attempt: activeAttempt,
            },
          })
        );
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // POST /rest/v1/rpc/initiate_payment_attempt
  if (req.method === 'POST' && pathname === '/rest/v1/rpc/initiate_payment_attempt') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { p_order_id, p_order_token, p_payment_type } = payload;

        const matchedOrder = mockOrders.find(
          (o) => o.id === p_order_id && o.order_token === p_order_token
        );

        if (!matchedOrder) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'ORDER_NOT_FOUND_OR_UNAUTHORIZED' }));
          return;
        }

        const pType = p_payment_type || (matchedOrder.confirmation_mode === 'advance' ? 'advance' : 'full');
        const expectedAmount =
          pType === 'advance'
            ? matchedOrder.advance_required_paisa
            : pType === 'balance'
            ? matchedOrder.balance_due_paisa
            : matchedOrder.total_paisa;

        const attemptId = crypto.randomUUID();
        const ref = `LD-${matchedOrder.order_code}-${pType.toUpperCase()}`;
        const upiUri = `upi://pay?pa=${encodeURIComponent(mockProfile.upi_id)}&pn=${encodeURIComponent(
          mockProfile.store_name
        )}&am=${(expectedAmount / 100).toFixed(2)}&cu=INR&tr=${ref}&tn=LiveDrop%20${matchedOrder.order_code}`;

        const attempt = {
          id: attemptId,
          order_id: matchedOrder.id,
          payment_type: pType,
          payment_method: 'upi',
          expected_amount_paisa: expectedAmount,
          payee_vpa_snapshot: mockProfile.upi_id,
          payee_display_name_snapshot: mockProfile.store_name,
          transaction_reference: ref,
          status: 'initiated',
          buyer_claimed_at: null,
          buyer_submitted_utr: null,
          seller_verified_at: null,
          rejection_reason: null,
          verification_expires_at: null,
          expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          upi_uri: upiUri,
        };

        mockPaymentAttempts.push(attempt);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            success: true,
            payment_attempt_id: attempt.id,
            order_id: matchedOrder.id,
            payment_type: pType,
            expected_amount_paisa: expectedAmount,
            payee_vpa: mockProfile.upi_id,
            payee_display_name: mockProfile.store_name,
            transaction_reference: ref,
            status: 'initiated',
            upi_uri: upiUri,
            verification_expires_at: null,
            expires_at: attempt.expires_at,
          })
        );
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // POST /rest/v1/rpc/submit_buyer_payment_claim
  if (req.method === 'POST' && pathname === '/rest/v1/rpc/submit_buyer_payment_claim') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { p_order_id, p_order_token, p_payment_attempt_id, p_utr } = payload;

        const matchedOrder = mockOrders.find(
          (o) => o.id === p_order_id && o.order_token === p_order_token
        );
        if (!matchedOrder) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'ORDER_NOT_FOUND_OR_UNAUTHORIZED' }));
          return;
        }

        const attempt = mockPaymentAttempts.find((a) => a.id === p_payment_attempt_id);
        if (!attempt) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'ATTEMPT_NOT_FOUND' }));
          return;
        }

        attempt.status = 'buyer_claimed';
        attempt.buyer_submitted_utr = p_utr;
        attempt.buyer_claimed_at = new Date().toISOString();
        attempt.verification_expires_at = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
        attempt.updated_at = new Date().toISOString();

        // Broadcast realtime change for order & payment attempt
        broadcastEvent(`buyer-order-${matchedOrder.id}`, 'payment_attempts', 'UPDATE', attempt);
        broadcastEvent(`buyer-order-${matchedOrder.id}`, 'orders', 'UPDATE', matchedOrder);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            success: true,
            payment_attempt_id: attempt.id,
            status: 'buyer_claimed',
            buyer_submitted_utr: p_utr,
            buyer_claimed_at: attempt.buyer_claimed_at,
            verification_expires_at: attempt.verification_expires_at,
            expires_at: attempt.expires_at,
          })
        );
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // POST /rest/v1/rpc/verify_manual_upi_payment
  if (req.method === 'POST' && pathname === '/rest/v1/rpc/verify_manual_upi_payment') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { p_payment_attempt_id, p_order_id } = payload;

        const attempt = mockPaymentAttempts.find(
          (a) => a.id === p_payment_attempt_id || (p_order_id ? a.order_id === p_order_id : false)
        );
        const orderId = attempt ? attempt.order_id : p_order_id;
        const matchedOrder = mockOrders.find((o) => o.id === orderId);

        if (!matchedOrder) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'ORDER_NOT_FOUND' }));
          return;
        }

        if (attempt) {
          attempt.status = 'verified';
          attempt.seller_verified_at = new Date().toISOString();
          attempt.updated_at = new Date().toISOString();
        }

        // Transition order status to paid / ready_to_ship
        matchedOrder.payment_status = 'paid';
        matchedOrder.status = 'paid';
        matchedOrder.fulfilment_status = 'ready_to_ship';
        matchedOrder.total_paid_paisa = matchedOrder.total_paisa;
        matchedOrder.balance_due_paisa = 0;
        matchedOrder.updated_at = new Date().toISOString();

        // Mark associated products as sold
        for (const item of matchedOrder.items) {
          const prod = mockProducts.find((p) => p.id === item.product_id);
          if (prod) {
            prod.status = 'sold';
            prod.version = (prod.version || 1) + 1;
            broadcastEvent(`realtime:drop:${matchedOrder.drop_id}:products`, 'products', 'UPDATE', prod);
          }
        }

        // Broadcast realtime update to buyer
        broadcastEvent(`buyer-order-${matchedOrder.id}`, 'orders', 'UPDATE', matchedOrder);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            success: true,
            order_id: matchedOrder.id,
            payment_status: 'paid',
            fulfilment_status: 'ready_to_ship',
            total_paid_paisa: matchedOrder.total_paid_paisa,
          })
        );
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // POST /rest/v1/rpc/mark_order_shipped
  if (req.method === 'POST' && pathname === '/rest/v1/rpc/mark_order_shipped') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { p_order_id, p_tracking_number, p_courier_partner, p_notes } = payload;

        const matchedOrder = mockOrders.find((o) => o.id === p_order_id);
        if (!matchedOrder) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: 'ORDER_NOT_FOUND' }));
          return;
        }

        matchedOrder.status = 'shipped';
        matchedOrder.fulfilment_status = 'shipped';
        matchedOrder.shipped_at = new Date().toISOString();
        matchedOrder.tracking_number = (p_tracking_number || '').trim();
        matchedOrder.courier_partner = (p_courier_partner || 'Courier Express').trim();
        matchedOrder.notes = p_notes || null;
        matchedOrder.updated_at = new Date().toISOString();

        // Broadcast realtime update to buyer
        broadcastEvent(`buyer-order-${matchedOrder.id}`, 'orders', 'UPDATE', matchedOrder);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            success: true,
            order_id: matchedOrder.id,
            status: 'shipped',
            fulfilment_status: 'shipped',
            tracking_number: matchedOrder.tracking_number,
            courier_partner: matchedOrder.courier_partner,
            shipped_at: matchedOrder.shipped_at,
          })
        );
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
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

  socket.on('data', (buffer) => {
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
