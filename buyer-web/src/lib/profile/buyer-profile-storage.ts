/**
 * LiveDrop — Guest-First Buyer Profile Storage (Screen 7)
 *
 * Persists patron preferences, display name, initials, address, wishlist, and notifications
 * safely on the client device.
 *
 * GUARANTEES:
 * 1. Default identity is "Guest Patron" with initials "GP".
 * 2. Checkout data does NOT silently overwrite a patron's custom display name.
 * 3. Recovers safely from malformed JSON or blocked localStorage.
 */

import { BuyerProfile, SavedShippingAddress } from '../../types/profile';

export const BUYER_PROFILE_STORAGE_KEY = 'livedrop_buyer_profile_v1';

let inMemoryProfile: string | null = null;

function getRawProfile(): string | null {
  if (typeof window === 'undefined') {
    return inMemoryProfile;
  }
  try {
    return window.localStorage.getItem(BUYER_PROFILE_STORAGE_KEY);
  } catch {
    return inMemoryProfile;
  }
}

function setRawProfile(val: string): boolean {
  if (typeof window === 'undefined') {
    inMemoryProfile = val;
    return true;
  }
  try {
    window.localStorage.setItem(BUYER_PROFILE_STORAGE_KEY, val);
    return true;
  } catch {
    inMemoryProfile = val;
    return false;
  }
}

export function generateInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'GP';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function createDefaultProfile(): BuyerProfile {
  return {
    displayName: 'Guest Patron',
    initials: 'GP',
    avatarUrl: null,
    phoneNumber: null,
    savedAddress: null,
    notificationsEnabled: false,
    wishlistProductIds: [],
    savedDropIds: [],
    updatedAt: Date.now(),
  };
}

export function loadStoredBuyerProfile(): BuyerProfile {
  const raw = getRawProfile();
  if (!raw) {
    return createDefaultProfile();
  }

  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return createDefaultProfile();
    }

    const displayName =
      typeof parsed.displayName === 'string' && parsed.displayName.trim() !== ''
        ? parsed.displayName.trim().slice(0, 50)
        : 'Guest Patron';

    const initials =
      typeof parsed.initials === 'string' && parsed.initials.trim() !== ''
        ? parsed.initials.trim().slice(0, 4).toUpperCase()
        : generateInitials(displayName);

    const avatarUrl =
      typeof parsed.avatarUrl === 'string' && parsed.avatarUrl.trim() !== ''
        ? parsed.avatarUrl.trim()
        : null;

    const phoneNumber =
      typeof parsed.phoneNumber === 'string' ? parsed.phoneNumber.trim().slice(0, 15) : null;

    let savedAddress: SavedShippingAddress | null = null;
    if (parsed.savedAddress && typeof parsed.savedAddress === 'object') {
      const a = parsed.savedAddress as Record<string, unknown>;
      if (
        typeof a.recipientName === 'string' &&
        typeof a.street === 'string' &&
        typeof a.city === 'string' &&
        typeof a.pincode === 'string' &&
        typeof a.state === 'string'
      ) {
        savedAddress = {
          recipientName: a.recipientName.slice(0, 100),
          street: a.street.slice(0, 200),
          city: a.city.slice(0, 100),
          pincode: a.pincode.slice(0, 10),
          state: a.state.slice(0, 100),
        };
      }
    }

    const notificationsEnabled = Boolean(parsed.notificationsEnabled);
    const wishlistProductIds = Array.isArray(parsed.wishlistProductIds)
      ? parsed.wishlistProductIds.filter((id: unknown): id is string => typeof id === 'string').slice(0, 50)
      : [];

    const savedDropIds = Array.isArray(parsed.savedDropIds)
      ? parsed.savedDropIds.filter((id: unknown): id is string => typeof id === 'string').slice(0, 50)
      : [];

    return {
      displayName,
      initials,
      avatarUrl,
      phoneNumber,
      savedAddress,
      notificationsEnabled,
      wishlistProductIds,
      savedDropIds,
      updatedAt: typeof parsed.updatedAt === 'number' ? parsed.updatedAt : Date.now(),
    };
  } catch {
    return createDefaultProfile();
  }
}

export function saveStoredBuyerProfile(profile: BuyerProfile): boolean {
  try {
    const payload = JSON.stringify({
      displayName: profile.displayName,
      initials: profile.initials,
      avatarUrl: profile.avatarUrl,
      phoneNumber: profile.phoneNumber,
      savedAddress: profile.savedAddress,
      notificationsEnabled: profile.notificationsEnabled,
      wishlistProductIds: profile.wishlistProductIds,
      savedDropIds: profile.savedDropIds,
      updatedAt: Date.now(),
    });
    return setRawProfile(payload);
  } catch {
    return false;
  }
}

export function clearStoredBuyerProfile(): void {
  inMemoryProfile = null;
  if (typeof window !== 'undefined') {
    try {
      window.localStorage.removeItem(BUYER_PROFILE_STORAGE_KEY);
    } catch {
      // ignore
    }
  }
}
