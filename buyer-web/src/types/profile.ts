/**
 * LiveDrop — Buyer Profile Domain Types
 *
 * Defines the persistent client-side buyer profile contract.
 * Initialized guest-first and stored locally on the device (localStorage).
 */

export interface SavedShippingAddress {
  recipientName: string;
  street: string;
  city: string;
  pincode: string;
  state: string;
}

export interface BuyerProfile {
  displayName: string;
  initials: string;
  avatarUrl?: string | null;
  phoneNumber?: string | null;
  savedAddress?: SavedShippingAddress | null;
  notificationsEnabled: boolean;
  wishlistProductIds: string[];
  savedDropIds: string[];
  updatedAt: number;
}
