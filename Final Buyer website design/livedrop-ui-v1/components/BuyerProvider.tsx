"use client";

import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { products } from "@/lib/data";
import type { CartItem } from "@/lib/types";

interface BuyerContextValue {
  cart: CartItem[];
  addToCart: (id: string) => void;
  increment: (id: string) => void;
  decrement: (id: string) => void;
  remove: (id: string) => void;
  clear: () => void;
  count: number;
  subtotal: number;
}

const BuyerContext = createContext<BuyerContextValue | null>(null);

const seed = (ids: string[]): CartItem[] => ids.map((id) => ({ product: products.find((p) => p.id === id)!, quantity: 1 }));

export function BuyerProvider({ children }: { children: React.ReactNode }) {
  const [cart, setCart] = useState<CartItem[]>(() => seed(["a01", "a02", "a03"]));

  useEffect(() => {
    const saved = window.localStorage.getItem("livedrop-ui-cart");
    if (!saved) return;
    try {
      const parsed = JSON.parse(saved) as CartItem[];
      if (Array.isArray(parsed) && parsed.length) {
        queueMicrotask(() => {
          setCart(parsed);
        });
      }
    } catch { /* demo */ }
  }, []);

  useEffect(() => {
    window.localStorage.setItem("livedrop-ui-cart", JSON.stringify(cart));
  }, [cart]);

  const value = useMemo<BuyerContextValue>(() => {
    const count = cart.reduce((sum, item) => sum + item.quantity, 0);
    const subtotal = cart.reduce((sum, item) => sum + item.product.price * item.quantity, 0);
    return {
      cart, count, subtotal,
      addToCart: (id) => setCart((prev) => {
        const next = [...prev];
        const existing = next.find((item) => item.product.id === id);
        if (existing) existing.quantity += 1;
        else next.push({ product: products.find((p) => p.id === id)!, quantity: 1 });
        return next;
      }),
      increment: (id) => setCart((prev) => prev.map((item) => item.product.id === id ? { ...item, quantity: item.quantity + 1 } : item)),
      decrement: (id) => setCart((prev) => prev.map((item) => item.product.id === id ? { ...item, quantity: Math.max(1, item.quantity - 1) } : item)),
      remove: (id) => setCart((prev) => prev.filter((item) => item.product.id !== id)),
      clear: () => setCart([]),
    };
  }, [cart]);

  return <BuyerContext.Provider value={value}>{children}</BuyerContext.Provider>;
}

export function useBuyer() {
  const ctx = useContext(BuyerContext);
  if (!ctx) throw new Error("useBuyer must be used inside BuyerProvider");
  return ctx;
}
