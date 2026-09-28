"use client";

import Link from "next/link";
import { AnimatePresence, motion } from "motion/react";
import { Search, ShoppingBag, UserRound, Menu, X } from "lucide-react";
import { useState } from "react";
import { useBuyer } from "@/components/BuyerProvider";

export function SiteHeader() {
  const { count } = useBuyer();
  const [open, setOpen] = useState(false);
  return (
    <>
      <div className="hidden lg:block border-b border-white/5 bg-black/20 px-4 py-2 text-[11px] text-white/55">
        <div className="mx-auto flex max-w-[1440px] items-center justify-between">
          <div className="flex gap-6"><span>Authentic Indian Fashion</span><span>Independent Boutiques</span><span>Secure Payments</span></div>
          <span className="text-[#f3c653]">Free shipping on select orders →</span>
        </div>
      </div>
      <header className="sticky top-0 z-50 border-b border-white/6 bg-[#080a09]/92 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-[1440px] items-center gap-3 px-4 lg:px-7">
          <button aria-label="Open menu" className="rounded-full border border-white/8 p-2 lg:hidden" onClick={() => setOpen(true)}><Menu size={20} /></button>
          <Link href="/" className="flex min-w-0 items-center gap-3">
            <span className="text-2xl leading-none text-[#f3c653]">✦</span>
            <span className="leading-none"><span className="ld-serif block text-xl lg:text-2xl">LiveDrop</span><span className="text-[9px] tracking-[.3em] text-[#cbbf9e]">INDIAN LUXURY LIVE</span></span>
          </Link>
          <nav className="ml-8 hidden gap-6 text-sm text-white/72 lg:flex">
            <Link className="hover:text-white" href="/">Home</Link>
            <Link className="hover:text-white" href="/shop">Shop</Link>
            <Link className="hover:text-white" href="/live">Live Drops</Link>
            <Link className="hover:text-white" href="/filters">Collections</Link>
            <Link className="hover:text-white" href="/shop#boutiques">Boutiques</Link>
          </nav>
          <div className="ml-auto flex items-center gap-2">
            <div className="hidden items-center gap-2 rounded-full border border-white/9 bg-white/[.03] px-3 py-2 lg:flex lg:w-72"><Search size={16} className="text-white/45"/><span className="truncate text-xs text-white/45">Search sarees, kurtis, dupattas...</span></div>
            <button aria-label="Search" className="rounded-full border border-white/8 p-2.5 lg:hidden"><Search size={19}/></button>
            <button aria-label="Profile" className="hidden rounded-full border border-white/8 p-2.5 lg:block"><UserRound size={18}/></button>
            <Link href="/cart" aria-label="Cart" className="relative rounded-full border border-white/8 p-2.5">
              <ShoppingBag size={18}/>
              {count > 0 && <span className="absolute -right-1 -top-1 min-w-5 rounded-full bg-[#f3c653] px-1.5 py-0.5 text-center text-[10px] font-black text-black">{count}</span>}
            </Link>
          </div>
        </div>
      </header>
      <AnimatePresence>
        {open && (
          <motion.div className="fixed inset-0 z-[70] bg-black/70 backdrop-blur-sm lg:hidden" initial={{opacity:0}} animate={{opacity:1}} exit={{opacity:0}} onClick={() => setOpen(false)}>
            <motion.aside className="h-full w-[84%] max-w-[340px] border-r border-white/8 bg-[#0c0e0c] p-5" initial={{x:-30}} animate={{x:0}} exit={{x:-30}} onClick={(e)=>e.stopPropagation()}>
              <div className="mb-8 flex items-center justify-between"><span className="ld-serif text-xl">LiveDrop</span><button aria-label="Close menu" onClick={()=>setOpen(false)}><X/></button></div>
              <nav className="grid gap-2 text-lg"><Link className="rounded-xl p-3 hover:bg-white/5" href="/" onClick={()=>setOpen(false)}>Home</Link><Link className="rounded-xl p-3 hover:bg-white/5" href="/shop" onClick={()=>setOpen(false)}>Shop</Link><Link className="rounded-xl p-3 hover:bg-white/5" href="/live" onClick={()=>setOpen(false)}>Live Drops</Link><Link className="rounded-xl p-3 hover:bg-white/5" href="/filters" onClick={()=>setOpen(false)}>Collections & Filters</Link></nav>
            </motion.aside>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
