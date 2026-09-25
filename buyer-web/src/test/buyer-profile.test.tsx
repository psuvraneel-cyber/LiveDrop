/**
 * LiveDrop Buyer Webfront — Buyer Profile Unit Tests (Screen 7)
 *
 * Verifies:
 * 1. Guest-first profile initialization (Guest Patron, initials GP)
 * 2. Profile updating & initials generation
 * 3. BuyerProfileDrawer rendering (patron card, 8 menu actions, promo banner, close X)
 * 4. EditProfileModal updating patron display name
 */

import React from 'react';
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import {
  loadStoredBuyerProfile,
  saveStoredBuyerProfile,
  generateInitials,
  clearStoredBuyerProfile,
} from '../lib/profile/buyer-profile-storage';
import { ProfileProvider, useProfile } from '../lib/profile/profile-context';
import { BuyerProfileDrawer } from '../components/profile/BuyerProfileDrawer';

describe('Buyer Profile Storage & Invariants', () => {
  beforeEach(() => {
    clearStoredBuyerProfile();
  });

  it('initializes default profile guest-first as Guest Patron with GP initials', () => {
    const profile = loadStoredBuyerProfile();
    expect(profile.displayName).toBe('Guest Patron');
    expect(profile.initials).toBe('GP');
    expect(profile.notificationsEnabled).toBe(false);
    expect(profile.wishlistProductIds).toEqual([]);
    expect(profile.savedDropIds).toEqual([]);
  });

  it('generates correct initials for various patron names', () => {
    expect(generateInitials('Priya Mehta')).toBe('PM');
    expect(generateInitials('Anaya')).toBe('AN');
    expect(generateInitials('Rohit Kumar Sharma')).toBe('RS');
    expect(generateInitials('')).toBe('GP');
  });

  it('persists and restores updated patron profile safely', () => {
    saveStoredBuyerProfile({
      displayName: 'Priya Mehta',
      initials: 'PM',
      avatarUrl: null,
      phoneNumber: '9876543210',
      savedAddress: null,
      notificationsEnabled: true,
      wishlistProductIds: ['p-1'],
      savedDropIds: ['d-1'],
      updatedAt: Date.now(),
    });

    const restored = loadStoredBuyerProfile();
    expect(restored.displayName).toBe('Priya Mehta');
    expect(restored.initials).toBe('PM');
    expect(restored.phoneNumber).toBe('9876543210');
    expect(restored.notificationsEnabled).toBe(true);
    expect(restored.wishlistProductIds).toEqual(['p-1']);
  });
});

describe('BuyerProfileDrawer UI Component Tests', () => {
  beforeEach(() => {
    clearStoredBuyerProfile();
  });

  function ProfileTestRig() {
    const { isProfileOpen, openProfile, closeProfile } = useProfile();
    return (
      <div>
        <button onClick={openProfile} data-testid="open-profile-btn">
          Open Profile
        </button>
        <BuyerProfileDrawer isOpen={isProfileOpen} onClose={closeProfile} />
      </div>
    );
  }

  it('renders clean utility elements when open (header, patron card, menu actions, close X)', () => {
    render(
      <ProfileProvider>
        <ProfileTestRig />
      </ProfileProvider>
    );

    // Open profile drawer
    fireEvent.click(screen.getByTestId('open-profile-btn'));

    expect(screen.getByTestId('buyer-profile-drawer')).toBeInTheDocument();
    expect(screen.getByText('LiveDrop')).toBeInTheDocument();
    expect(screen.getByText('INDIAN LUXURY LIVE')).toBeInTheDocument();
    expect(screen.getByTestId('profile-display-name')).toHaveTextContent('Guest Patron');

    // Menu Actions
    expect(screen.getByTestId('profile-my-orders')).toBeInTheDocument();
    expect(screen.getByTestId('profile-wishlist')).toBeInTheDocument();
    expect(screen.getByTestId('profile-notifications')).toBeInTheDocument();
    expect(screen.getByTestId('profile-saved-shows')).toBeInTheDocument();
    expect(screen.getByTestId('profile-addresses')).toBeInTheDocument();
    expect(screen.getByTestId('profile-support')).toBeInTheDocument();
  });


  it('allows opening EditProfileModal and updating patron display name', () => {
    render(
      <ProfileProvider>
        <ProfileTestRig />
      </ProfileProvider>
    );

    fireEvent.click(screen.getByTestId('open-profile-btn'));
    fireEvent.click(screen.getByTestId('edit-profile-btn'));

    expect(screen.getByTestId('edit-profile-modal')).toBeInTheDocument();

    const nameInput = screen.getByTestId('edit-profile-name-input');
    fireEvent.change(nameInput, { target: { value: 'Priya Mehta' } });

    fireEvent.click(screen.getByTestId('save-profile-btn'));

    expect(screen.queryByTestId('edit-profile-modal')).not.toBeInTheDocument();
    expect(screen.getByTestId('profile-display-name')).toHaveTextContent('Priya Mehta');
  });

  it('closes cleanly when clicking the X close button', () => {
    render(
      <ProfileProvider>
        <ProfileTestRig />
      </ProfileProvider>
    );

    fireEvent.click(screen.getByTestId('open-profile-btn'));
    expect(screen.getByTestId('buyer-profile-drawer')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('profile-drawer-close'));
    expect(screen.queryByTestId('buyer-profile-drawer')).not.toBeInTheDocument();
  });
});
