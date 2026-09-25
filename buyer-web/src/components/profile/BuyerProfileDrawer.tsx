'use client';

/**
 * LiveDrop — Screen 7: Buyer Profile Drawer
 *
 * Full-fidelity implementation of Screen 7 from the Haute Couture template.
 * Features guest-first persistent identity, luxury typography, full menu suite,
 * and early access notification callout.
 */

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { useProfile } from '../../lib/profile/profile-context';
import { EditProfileModal } from './EditProfileModal';

export interface BuyerProfileDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export function BuyerProfileDrawer({ isOpen, onClose }: BuyerProfileDrawerProps) {
  const { profile, updateProfile } = useProfile();
  const [isEditOpen, setIsEditOpen] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  // Close on Escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  // Lock body scroll when drawer is open
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 3000);
  };

  const handleToggleNotifications = async () => {
    if ('Notification' in window) {
      if (Notification.permission === 'granted') {
        const nextState = !profile.notificationsEnabled;
        updateProfile({ notificationsEnabled: nextState });
        showToast(nextState ? 'Notifications active' : 'Notifications paused');
      } else if (Notification.permission !== 'denied') {
        const permission = await Notification.requestPermission();
        if (permission === 'granted') {
          updateProfile({ notificationsEnabled: true });
          showToast('Live drop alerts enabled!');
        } else {
          showToast('Permission not granted');
        }
      } else {
        showToast('Notifications blocked in browser settings');
      }
    } else {
      const nextState = !profile.notificationsEnabled;
      updateProfile({ notificationsEnabled: nextState });
      showToast(nextState ? 'Notifications enabled in profile' : 'Notifications disabled');
    }
  };

  if (!isOpen) return null;

  return (
    <>
      <div
        className="fixed inset-0 z-[100] bg-black/80 backdrop-blur-md transition-opacity duration-300 flex justify-end"
        onClick={onClose}
        data-testid="buyer-profile-backdrop"
        role="presentation"
      >
        <div
          className="w-full max-w-md h-full bg-[#090909] border-l border-white/10 shadow-2xl flex flex-col overflow-y-auto scrollbar-none animate-slide-in-right text-[#F4F1EA]"
          onClick={(e) => e.stopPropagation()}
          role="dialog"
          aria-modal="true"
          aria-labelledby="profile-drawer-title"
          data-testid="buyer-profile-drawer"
        >
          {/* 1. Header: Monogram Brand + Close '✕' Button */}
          <div className="flex items-center justify-between px-5 py-4 border-b border-white/10 sticky top-0 bg-[#08080A]/95 backdrop-blur-md z-10">
            <div className="flex items-center gap-2">
              <span className="text-[#D4AF37] text-base" aria-hidden="true">✦</span>
              <div className="flex flex-col">
                <span id="profile-drawer-title" className="font-serif text-lg tracking-wider text-[#FBFBFB] leading-none">
                  LiveDrop
                </span>
                <span className="text-[9px] font-mono tracking-widest text-[#D4AF37] uppercase">
                  INDIAN LUXURY LIVE
                </span>
              </div>
            </div>

            <button
              type="button"
              onClick={onClose}
              className="w-8 h-8 rounded-full bg-white/5 border border-white/10 hover:bg-white/10 flex items-center justify-center text-white/70 hover:text-white transition-colors"
              aria-label="Close profile drawer"
              data-testid="profile-drawer-close"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </div>

          <div className="p-5 space-y-6 flex-1">
            {/* 2. Patron Identity Card */}
            <div className="p-4 rounded-2xl bg-[#101014] border border-[rgba(212,175,55,0.25)] flex items-center justify-between shadow-lg">
              <div className="flex items-center gap-3.5">
                <div className="w-12 h-12 rounded-full bg-gradient-to-br from-[#2A0811] to-[#101014] border-2 border-[#D4AF37] flex items-center justify-center font-serif text-base font-bold text-[#F3E5AB] shadow-md shadow-[rgba(212,175,55,0.2)]">
                  {profile.initials}
                </div>
                <div>
                  <h2 className="text-base font-serif font-medium text-white tracking-wide" data-testid="profile-display-name">
                    {profile.displayName}
                  </h2>
                  <span className="text-xs text-white/50 font-sans">
                    {profile.phoneNumber ? `+91 ${profile.phoneNumber}` : 'Verified Guest Patron'}
                  </span>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setIsEditOpen(true)}
                className="text-xs text-[#D4AF37] hover:text-[#F5D78E] font-medium tracking-wide flex items-center gap-1 transition-colors"
                data-testid="edit-profile-btn"
              >
                <span>Edit Profile</span>
                <span aria-hidden="true">→</span>
              </button>
            </div>

            {/* Toast notice */}
            {toastMessage && (
              <div className="p-2.5 rounded-lg bg-[rgba(212,175,55,0.15)] border border-[rgba(212,175,55,0.3)] text-xs text-[#F3E5AB] text-center font-medium animate-fade-in">
                {toastMessage}
              </div>
            )}

            {/* 3. Luxury Patron Menu Items (Screen 7 List) */}
            <nav className="space-y-1 rounded-2xl bg-[#0D0D10] border border-white/5 p-2 shadow-inner" aria-label="Patron Account Menu">
              {/* My Orders */}
              <Link
                href="/order"
                onClick={onClose}
                className="w-full px-4 py-3 rounded-xl flex items-center justify-between hover:bg-white/5 text-white/85 hover:text-white transition-all group"
                data-testid="profile-my-orders"
              >
                <div className="flex items-center gap-3">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-[#D4AF37]">
                    <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                    <path d="M3 6h18" />
                    <path d="M16 10a4 4 0 0 1-8 0" />
                  </svg>
                  <span className="text-sm font-medium tracking-wide">My Orders</span>
                </div>
                <span className="text-xs text-white/40 group-hover:text-[#D4AF37] transition-colors">View →</span>
              </Link>

              {/* Wishlist */}
              <div
                className="w-full px-4 py-3 rounded-xl flex items-center justify-between hover:bg-white/5 text-white/85 transition-all cursor-pointer"
                onClick={() => showToast(profile.wishlistProductIds.length > 0 ? `${profile.wishlistProductIds.length} item(s) in wishlist` : 'Wishlist is empty')}
                data-testid="profile-wishlist"
              >
                <div className="flex items-center gap-3">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-[#D4AF37]">
                    <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
                  </svg>
                  <span className="text-sm font-medium tracking-wide">Wishlist</span>
                </div>
                <span className="text-xs text-[#D4AF37] font-mono font-medium">
                  {profile.wishlistProductIds.length}
                </span>
              </div>

              {/* Live Notifications */}
              <button
                type="button"
                onClick={handleToggleNotifications}
                className="w-full px-4 py-3 rounded-xl flex items-center justify-between hover:bg-white/5 text-white/85 transition-all text-left"
                data-testid="profile-notifications"
              >
                <div className="flex items-center gap-3">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-[#D4AF37]">
                    <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
                    <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
                  </svg>
                  <span className="text-sm font-medium tracking-wide">Live Notifications</span>
                </div>
                <span className={`text-xs px-2 py-0.5 rounded-full font-mono font-semibold ${profile.notificationsEnabled ? 'bg-[rgba(212,175,55,0.2)] text-[#D4AF37]' : 'bg-white/5 text-white/40'}`}>
                  {profile.notificationsEnabled ? 'Active' : 'Off'}
                </span>
              </button>

              {/* Saved Shows */}
              <div
                className="w-full px-4 py-3 rounded-xl flex items-center justify-between hover:bg-white/5 text-white/85 transition-all cursor-pointer"
                onClick={() => showToast(profile.savedDropIds.length > 0 ? `${profile.savedDropIds.length} saved live show(s)` : 'No saved shows yet')}
                data-testid="profile-saved-shows"
              >
                <div className="flex items-center gap-3">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-[#D4AF37]">
                    <path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z" />
                  </svg>
                  <span className="text-sm font-medium tracking-wide">Saved Shows</span>
                </div>
                <span className="text-xs text-[#D4AF37] font-mono font-medium">
                  {profile.savedDropIds.length}
                </span>
              </div>

              {/* Addresses */}
              <div
                className="w-full px-4 py-3 rounded-xl flex items-center justify-between hover:bg-white/5 text-white/85 transition-all cursor-pointer"
                onClick={() => showToast(profile.savedAddress ? `${profile.savedAddress.city}, ${profile.savedAddress.pincode}` : 'Saved automatically at checkout')}
                data-testid="profile-addresses"
              >
                <div className="flex items-center gap-3">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-[#C79A45]">
                    <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
                    <circle cx="12" cy="10" r="3" />
                  </svg>
                  <span className="text-sm font-medium tracking-wide">Addresses</span>
                </div>
                <span className="text-xs text-white/40">Manage →</span>
              </div>

              {/* Help & Support */}
              <a
                href="https://wa.me/917439583884?text=Hi%20LiveDrop%20Concierge%2C%20I%20need%20assistance%20with%20my%20order."
                target="_blank"
                rel="noopener noreferrer"
                className="w-full px-4 py-3 rounded-xl flex items-center justify-between hover:bg-white/5 text-white/85 hover:text-white transition-all group"
                data-testid="profile-support"
              >
                <div className="flex items-center gap-3">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-[#C79A45]">
                    <circle cx="12" cy="12" r="10" />
                    <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
                    <path d="M12 17h.01" />
                  </svg>
                  <span className="text-sm font-medium tracking-wide">Help & Support</span>
                </div>
                <span className="text-xs text-[#25D366] font-medium">WhatsApp →</span>
              </a>
            </nav>
          </div>
        </div>
      </div>

      <EditProfileModal isOpen={isEditOpen} onClose={() => setIsEditOpen(false)} />
    </>
  );
}
