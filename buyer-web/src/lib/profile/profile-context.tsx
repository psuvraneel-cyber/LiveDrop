'use client';

/**
 * LiveDrop — Buyer Profile Context & State Manager (Screen 7)
 *
 * Provides reactive access to buyer profile state and drawer controls.
 */

import React, {
  createContext,
  useContext,
  useState,
  useCallback,
  useMemo,
  useEffect,
  ReactNode,
} from 'react';
import { BuyerProfile } from '../../types/profile';
import {
  loadStoredBuyerProfile,
  saveStoredBuyerProfile,
  generateInitials,
  BUYER_PROFILE_STORAGE_KEY,
} from './buyer-profile-storage';

export interface ProfileContextValue {
  profile: BuyerProfile;
  isProfileOpen: boolean;
  openProfile: () => void;
  closeProfile: () => void;
  toggleProfile: () => void;
  updateProfile: (updates: Partial<BuyerProfile>) => void;
  toggleWishlist: (productId: string) => void;
  toggleSavedDrop: (dropId: string) => void;
  isWishlisted: (productId: string) => boolean;
  isDropSaved: (dropId: string) => boolean;
}

const ProfileContext = createContext<ProfileContextValue | null>(null);

export function ProfileProvider({ children }: { children: ReactNode }) {
  const [profile, setProfile] = useState<BuyerProfile>(loadStoredBuyerProfile);
  const [isProfileOpen, setIsProfileOpen] = useState(false);

  // Sync across tabs
  useEffect(() => {
    const handleStorage = (e: StorageEvent) => {
      if (e.key === BUYER_PROFILE_STORAGE_KEY) {
        setProfile(loadStoredBuyerProfile());
      }
    };
    window.addEventListener('storage', handleStorage);
    return () => window.removeEventListener('storage', handleStorage);
  }, []);

  const openProfile = useCallback(() => setIsProfileOpen(true), []);
  const closeProfile = useCallback(() => setIsProfileOpen(false), []);
  const toggleProfile = useCallback(() => setIsProfileOpen((prev) => !prev), []);

  const updateProfile = useCallback((updates: Partial<BuyerProfile>) => {
    setProfile((prev) => {
      const nextName = updates.displayName !== undefined ? updates.displayName : prev.displayName;
      const nextInitials =
        updates.initials !== undefined
          ? updates.initials
          : updates.displayName !== undefined
          ? generateInitials(updates.displayName)
          : prev.initials;

      const next: BuyerProfile = {
        ...prev,
        ...updates,
        displayName: nextName,
        initials: nextInitials,
        updatedAt: Date.now(),
      };
      saveStoredBuyerProfile(next);
      return next;
    });
  }, []);

  const toggleWishlist = useCallback((productId: string) => {
    setProfile((prev) => {
      const exists = prev.wishlistProductIds.includes(productId);
      const nextList = exists
        ? prev.wishlistProductIds.filter((id) => id !== productId)
        : [...prev.wishlistProductIds, productId];

      const next: BuyerProfile = {
        ...prev,
        wishlistProductIds: nextList,
        updatedAt: Date.now(),
      };
      saveStoredBuyerProfile(next);
      return next;
    });
  }, []);

  const toggleSavedDrop = useCallback((dropId: string) => {
    setProfile((prev) => {
      const exists = prev.savedDropIds.includes(dropId);
      const nextList = exists
        ? prev.savedDropIds.filter((id) => id !== dropId)
        : [...prev.savedDropIds, dropId];

      const next: BuyerProfile = {
        ...prev,
        savedDropIds: nextList,
        updatedAt: Date.now(),
      };
      saveStoredBuyerProfile(next);
      return next;
    });
  }, []);

  const isWishlisted = useCallback(
    (productId: string) => profile.wishlistProductIds.includes(productId),
    [profile.wishlistProductIds]
  );

  const isDropSaved = useCallback(
    (dropId: string) => profile.savedDropIds.includes(dropId),
    [profile.savedDropIds]
  );

  const value = useMemo<ProfileContextValue>(
    () => ({
      profile,
      isProfileOpen,
      openProfile,
      closeProfile,
      toggleProfile,
      updateProfile,
      toggleWishlist,
      toggleSavedDrop,
      isWishlisted,
      isDropSaved,
    }),
    [
      profile,
      isProfileOpen,
      openProfile,
      closeProfile,
      toggleProfile,
      updateProfile,
      toggleWishlist,
      toggleSavedDrop,
      isWishlisted,
      isDropSaved,
    ]
  );

  return <ProfileContext.Provider value={value}>{children}</ProfileContext.Provider>;
}

export function useProfile(): ProfileContextValue {
  const context = useContext(ProfileContext);
  if (!context) {
    throw new Error('useProfile must be used within a ProfileProvider');
  }
  return context;
}

export function useOptionalProfile(): ProfileContextValue | null {
  return useContext(ProfileContext);
}
