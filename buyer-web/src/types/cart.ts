/**
 * LiveDrop — Buyer Cart Domain & Storage Contracts (TASK-2.2)
 *
 * All monetary values are non-negative integers in Paisa (ADR-009).
 * The buyer cart is purely client-side intent and MUST NOT reserve inventory.
 */

export interface CartItem {
  productId: string; // UUID references products(id)
  dropId: string; // UUID references drops(id)
  code: string; // Flash code (e.g., '#A01')
  title: string;
  pricePaisa: number; // Integer Paisa (e.g., 185000 = ₹1,850.00)
  imageUrl: string;
  size: string;
  addedAt: number; // Unix epoch timestamp ms
}

export interface ReconciledCartItem extends CartItem {
  status: 'available' | 'reserved' | 'sold';
  isAvailable: boolean;
  availabilityReason?: string;
}

export interface CartStorageSchema {
  version: 1;
  dropId: string | null;
  items: CartItem[];
  orderNote?: string;
  updatedAt: number;
}
