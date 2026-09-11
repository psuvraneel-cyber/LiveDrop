'use client';

/**
 * LiveDrop — Buyer Cart Context & State Manager (TASK-2.2)
 *
 * Implements client-side cart state with local persistence via useSyncExternalStore,
 * single-piece inventory enforcement, integer Paisa totals, and catalog availability reconciliation.
 *
 * CRITICAL RULE: Cart state is buyer intent ONLY. It NEVER reserves inventory.
 */

import React, {
  createContext,
  useContext,
  useState,
  useCallback,
  useMemo,
  useSyncExternalStore,
  ReactNode,
} from 'react';
import { CartItem, CartStorageSchema, ReconciledCartItem } from '../../types/cart';
import { PublicProductView } from '../../types/domain';
import {
  CART_STORAGE_KEY,
  CURRENT_CART_SCHEMA_VERSION,
  createEmptyCart,
  loadStoredCart,
  saveStoredCart,
  clearStoredCart as clearStorage,
} from './cart-storage';

export type AddToCartResult =
  | { success: true }
  | { success: false; reason: 'ALREADY_IN_CART' | 'DIFFERENT_DROP' | 'UNAVAILABLE' | 'LIMIT_EXCEEDED' };

export interface CartContextValue {
  items: CartItem[];
  itemCount: number;
  subtotalPaisa: number;
  dropId: string | null;
  isHydrated: boolean;
  isDrawerOpen: boolean;
  addItem: (product: PublicProductView, dropId: string) => AddToCartResult;
  replaceCartWithItem: (product: PublicProductView, dropId: string) => void;
  removeItem: (productId: string) => void;
  clearCart: () => void;
  isInCart: (productId: string) => boolean;
  getReconciledItems: (catalogProducts: PublicProductView[]) => ReconciledCartItem[];
  openDrawer: () => void;
  closeDrawer: () => void;
  toggleDrawer: () => void;
}

const CartContext = createContext<CartContextValue | null>(null);

export const MAX_CART_ITEMS = 10; // RULE-ORD-04

// In-memory external store singleton for synchronization across components & tabs
let memoryCart: CartStorageSchema = createEmptyCart();
let isInitialized = false;
const listeners = new Set<() => void>();

function notifyListeners() {
  for (const listener of listeners) {
    listener();
  }
}

function getClientSnapshot(): CartStorageSchema {
  if (typeof window !== 'undefined' && !isInitialized) {
    memoryCart = loadStoredCart();
    isInitialized = true;
  }
  return memoryCart;
}

const SERVER_SNAPSHOT: CartStorageSchema = {
  version: CURRENT_CART_SCHEMA_VERSION,
  dropId: null,
  items: [],
  updatedAt: 0,
};

function getServerSnapshot(): CartStorageSchema {
  return SERVER_SNAPSHOT;
}

function subscribeToStore(callback: () => void): () => void {
  listeners.add(callback);

  const handleStorage = (e: StorageEvent) => {
    if (e.key === CART_STORAGE_KEY) {
      memoryCart = loadStoredCart();
      notifyListeners();
    }
  };

  if (typeof window !== 'undefined') {
    window.addEventListener('storage', handleStorage);
  }

  return () => {
    listeners.delete(callback);
    if (typeof window !== 'undefined') {
      window.removeEventListener('storage', handleStorage);
    }
  };
}

/**
 * Resets the in-memory singleton cart state (used in testing).
 */
export function resetCartStore(): void {
  memoryCart = createEmptyCart();
  isInitialized = false;
  notifyListeners();
}

function setStoreCart(nextItems: CartItem[], nextDropId: string | null) {
  memoryCart = {
    version: CURRENT_CART_SCHEMA_VERSION,
    dropId: nextDropId,
    items: nextItems,
    updatedAt: Date.now(),
  };
  saveStoredCart(memoryCart);
  notifyListeners();
}

function subscribeNoop(): () => void {
  return () => {};
}

function getHydratedClient(): boolean {
  return true;
}

function getHydratedServer(): boolean {
  return false;
}

export function CartProvider({ children }: { children: ReactNode }) {
  const cartSnapshot = useSyncExternalStore(subscribeToStore, getClientSnapshot, getServerSnapshot);
  const isHydrated = useSyncExternalStore(subscribeNoop, getHydratedClient, getHydratedServer);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);

  const items = cartSnapshot.items;
  const dropId = cartSnapshot.dropId;

  const isInCart = useCallback(
    (productId: string) => {
      return memoryCart.items.some((item) => item.productId === productId);
    },
    []
  );

  const addItem = useCallback(
    (product: PublicProductView, targetDropId: string): AddToCartResult => {
      if (product.status !== 'available') {
        return { success: false, reason: 'UNAVAILABLE' };
      }

      const currentItems = memoryCart.items;
      const currentDropId = memoryCart.dropId;

      // Single-piece invariant: duplicate adds are prevented
      if (currentItems.some((item) => item.productId === product.id)) {
        return { success: false, reason: 'ALREADY_IN_CART' };
      }

      // Cart limit: max 10 items (RULE-ORD-04)
      if (currentItems.length >= MAX_CART_ITEMS) {
        return { success: false, reason: 'LIMIT_EXCEEDED' };
      }

      // Drop boundary guard: cannot mix products from different drops
      if (currentDropId !== null && currentItems.length > 0 && currentDropId !== targetDropId) {
        return { success: false, reason: 'DIFFERENT_DROP' };
      }

      const newItem: CartItem = {
        productId: product.id,
        dropId: targetDropId,
        code: product.code,
        title: product.title,
        pricePaisa: Math.floor(product.price_paisa),
        imageUrl: product.image_url,
        size: product.size || '',
        addedAt: Date.now(),
      };

      const nextItems = [...currentItems, newItem];
      setStoreCart(nextItems, targetDropId);

      return { success: true };
    },
    []
  );

  const replaceCartWithItem = useCallback(
    (product: PublicProductView, targetDropId: string) => {
      if (product.status !== 'available') {
        return;
      }

      const newItem: CartItem = {
        productId: product.id,
        dropId: targetDropId,
        code: product.code,
        title: product.title,
        pricePaisa: Math.floor(product.price_paisa),
        imageUrl: product.image_url,
        size: product.size || '',
        addedAt: Date.now(),
      };

      setStoreCart([newItem], targetDropId);
    },
    []
  );

  const removeItem = useCallback(
    (productId: string) => {
      const nextItems = memoryCart.items.filter((item) => item.productId !== productId);
      const nextDropId = nextItems.length === 0 ? null : memoryCart.dropId;

      if (nextItems.length === 0) {
        clearStorage();
        memoryCart = createEmptyCart();
        notifyListeners();
      } else {
        setStoreCart(nextItems, nextDropId);
      }
    },
    []
  );

  const clearCart = useCallback(() => {
    clearStorage();
    memoryCart = createEmptyCart();
    notifyListeners();
  }, []);

  // Reconciles cart items against authoritative catalog snapshot or realtime products
  const getReconciledItems = useCallback(
    (catalogProducts: PublicProductView[]): ReconciledCartItem[] => {
      const catalogMap = new Map<string, PublicProductView>();
      for (const p of catalogProducts) {
        catalogMap.set(p.id, p);
      }

      return items.map((cartItem) => {
        const catalogProduct = catalogMap.get(cartItem.productId);

        if (!catalogProduct) {
          // If not in catalog list (or removed), treat as unavailable
          return {
            ...cartItem,
            status: 'sold',
            isAvailable: false,
          };
        }

        const isAvailable = catalogProduct.status === 'available';

        return {
          ...cartItem,
          // Update presentation fields from authoritative catalog
          title: catalogProduct.title,
          pricePaisa: Math.floor(catalogProduct.price_paisa),
          imageUrl: catalogProduct.image_url || cartItem.imageUrl,
          size: catalogProduct.size || cartItem.size,
          status: catalogProduct.status,
          isAvailable,
        };
      });
    },
    [items]
  );

  // Integer Paisa subtotal: sum(item.pricePaisa)
  const subtotalPaisa = useMemo(() => {
    return items.reduce((sum, item) => sum + Math.floor(item.pricePaisa), 0);
  }, [items]);

  const itemCount = items.length;

  const openDrawer = useCallback(() => setIsDrawerOpen(true), []);
  const closeDrawer = useCallback(() => setIsDrawerOpen(false), []);
  const toggleDrawer = useCallback(() => setIsDrawerOpen((prev) => !prev), []);

  const value = useMemo<CartContextValue>(
    () => ({
      items,
      itemCount,
      subtotalPaisa,
      dropId,
      isHydrated,
      isDrawerOpen,
      addItem,
      replaceCartWithItem,
      removeItem,
      clearCart,
      isInCart,
      getReconciledItems,
      openDrawer,
      closeDrawer,
      toggleDrawer,
    }),
    [
      items,
      itemCount,
      subtotalPaisa,
      dropId,
      isHydrated,
      isDrawerOpen,
      addItem,
      replaceCartWithItem,
      removeItem,
      clearCart,
      isInCart,
      getReconciledItems,
      openDrawer,
      closeDrawer,
      toggleDrawer,
    ]
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useOptionalCart(): CartContextValue | null {
  return useContext(CartContext);
}

export function useCart(): CartContextValue {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error('useCart must be used within a CartProvider');
  }
  return context;
}
