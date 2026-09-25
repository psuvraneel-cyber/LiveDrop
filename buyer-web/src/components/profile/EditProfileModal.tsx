'use client';

import React, { useState } from 'react';
import { useProfile } from '../../lib/profile/profile-context';

export interface EditProfileModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function EditProfileModal({ isOpen, onClose }: EditProfileModalProps) {
  const { profile, updateProfile } = useProfile();
  const [name, setName] = useState(profile.displayName);
  const [phone, setPhone] = useState(profile.phoneNumber || '');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (name.trim()) {
      updateProfile({
        displayName: name.trim(),
        phoneNumber: phone.trim() || null,
      });
      onClose();
    }
  };

  return (
    <div
      className="fixed inset-0 z-[120] bg-black/80 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
      data-testid="edit-profile-modal"
    >
      <div
        className="w-full max-w-sm rounded-2xl bg-[#101014] border border-[rgba(212,175,55,0.3)] p-6 space-y-4 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="edit-profile-title"
      >
        <div className="flex items-center justify-between border-b border-white/10 pb-3">
          <h3 id="edit-profile-title" className="text-base font-serif tracking-wide text-[#FBFBFB]">
            Edit Patron Profile
          </h3>
          <button
            type="button"
            onClick={onClose}
            className="text-white/50 hover:text-white p-1 rounded-full text-lg leading-none"
            aria-label="Close edit profile dialog"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <label htmlFor="patron-name" className="text-xs font-mono uppercase tracking-wider text-white/70">
              Your Name
            </label>
            <input
              id="patron-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Priya Mehta"
              maxLength={50}
              required
              className="w-full px-3.5 py-2.5 rounded-lg bg-black/60 border border-white/15 text-white text-sm focus:outline-none focus:border-[#D4AF37] transition-colors"
              data-testid="edit-profile-name-input"
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="patron-phone" className="text-xs font-mono uppercase tracking-wider text-white/70">
              Mobile (Optional)
            </label>
            <input
              id="patron-phone"
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="10-digit mobile number"
              maxLength={15}
              className="w-full px-3.5 py-2.5 rounded-lg bg-black/60 border border-white/15 text-white text-sm focus:outline-none focus:border-[#D4AF37] transition-colors"
              data-testid="edit-profile-phone-input"
            />
          </div>

          <div className="pt-2 flex gap-2 justify-end">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-full border border-white/20 text-white/70 hover:text-white text-xs font-medium tracking-wide transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2 rounded-full bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] text-xs font-bold tracking-wider uppercase transition-all shadow-md shadow-[rgba(212,175,55,0.25)] hover:scale-102"
              data-testid="save-profile-btn"
            >
              Save Profile
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
