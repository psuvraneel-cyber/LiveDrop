"use client";
import Link from "next/link";
import { Home, Radio, ShoppingBag, ClipboardList } from "lucide-react";
import { useBuyer } from "@/components/BuyerProvider";

export function MobileBottomNav({ active = "home" }: { active?: string }) {
  const { count } = useBuyer();
  const items = [
    ["home", "Home", "/", Home], ["live", "Live", "/live", Radio], ["shop", "Shop", "/shop", ShoppingBag], ["orders", "Orders", "/order", ClipboardList], ["bag", "Bag", "/cart", ShoppingBag],
  ] as const;
  return <nav className="fixed bottom-0 left-0 right-0 z-50 border-t border-white/8 bg-[#080a09]/92 backdrop-blur-xl lg:hidden" style={{paddingBottom:"env(safe-area-inset-bottom)"}}><div className="grid grid-cols-5">
    {items.map(([key,label,href,Icon]) => <Link key={key} href={href} className={`relative flex min-h-16 flex-col items-center justify-center gap-1 text-[11px] ${active===key?"text-[#f3c653]":"text-white/55"}`}><Icon size={20}/><span>{label}</span>{key==="bag" && count>0 && <span className="absolute right-[17%] top-2 min-w-5 rounded-full bg-[#f3c653] px-1.5 py-0.5 text-[9px] font-black text-black">{count}</span>}{active===key && <span className="absolute top-0 h-0.5 w-8 rounded-full bg-[#f3c653]"/>}</Link>)}
  </div></nav>;
}
