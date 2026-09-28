"use client";
import Link from "next/link";
import { motion } from "motion/react";
import { Heart, MessageCircle, Share2, ShoppingBag, Send } from "lucide-react";
import { useState } from "react";
import { MobileBottomNav } from "@/components/MobileBottomNav";
import { boutiques, products } from "@/lib/data";
import { useBuyer } from "@/components/BuyerProvider";

export default function LivePage() {
  const boutique = boutiques[0];
  const product = products[0];
  const { addToCart } = useBuyer();
  const [heart, setHeart] = useState(0);
  const [chat, setChat] = useState("");
  const [messages, setMessages] = useState<string[]>([]);

  return (
    <main className="min-h-screen bg-black pb-20 lg:pb-0">
      <div className="mx-auto min-h-screen w-full max-w-[1600px] lg:grid lg:grid-cols-[minmax(0,1fr)_420px]">
        <section className="relative min-h-[88vh] overflow-hidden lg:min-h-screen">
          <img src={product.images[2]} alt="" className="absolute inset-0 h-full w-full object-cover" />
          <div className="absolute inset-0 bg-gradient-to-b from-black/75 via-black/10 to-black/85" />
          <div className="relative z-10 flex items-start justify-between p-4 lg:p-6">
            <div className="flex items-center gap-3">
              <img src={boutique.avatar} alt="" className="h-11 w-11 rounded-full border border-[#f3c653]" />
              <div>
                <div className="font-semibold">{boutique.name} ✓</div>
                <div className="text-xs text-white/65">{boutique.viewers} watching</div>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button className="ld-gold-button min-h-9 px-4 text-xs">Follow</button>
              <Link href="/cart" className="grid h-10 w-10 place-items-center rounded-full bg-black/40 backdrop-blur">
                <ShoppingBag size={18} />
              </Link>
            </div>
          </div>
          <div className="absolute left-4 top-28 flex gap-2">
            <span className="rounded-full bg-[#ff375f] px-3 py-1 text-xs font-bold">● LIVE</span>
            <span className="rounded-full bg-black/55 px-3 py-1 text-xs">◉ {boutique.viewers}</span>
          </div>
          <div className="absolute right-3 top-1/2 flex -translate-y-1/2 flex-col gap-3">
            <motion.button
              whileTap={{ scale: 0.85 }}
              onClick={() => setHeart((v) => v + 1)}
              className="grid h-12 w-12 place-items-center rounded-full border border-white/15 bg-black/35 backdrop-blur"
            >
              <Heart size={22} className="text-pink-300" />
            </motion.button>
            <span className="text-center text-xs">{4200 + heart}</span>
            <button className="grid h-12 w-12 place-items-center rounded-full border border-white/15 bg-black/35 backdrop-blur">
              <MessageCircle />
            </button>
            <button className="grid h-12 w-12 place-items-center rounded-full border border-white/15 bg-black/35 backdrop-blur">
              <Share2 />
            </button>
          </div>
          <div className="absolute bottom-5 left-4 right-4 lg:hidden">
            <div className="mb-3 max-w-[80%] space-y-2">
              {["This is beautiful! 😍", "Is this pure silk?", "Love the color 💜"].map((m, i) => (
                <div key={m} className="rounded-2xl bg-black/40 px-3 py-2 text-sm backdrop-blur">
                  <span className="font-semibold">{["Priya", "Amit", "Sneha"][i]} </span>
                  {m}
                </div>
              ))}
            </div>
            <div className="rounded-2xl border border-white/8 bg-black/60 p-2 backdrop-blur">
              <div className="flex items-center gap-2">
                <input
                  value={chat}
                  onChange={(e) => setChat(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && chat.trim()) {
                      setMessages((v) => [...v, chat.trim()]);
                      setChat("");
                    }
                  }}
                  className="w-full bg-transparent px-2 py-2 outline-none"
                  placeholder="Say something..."
                />
                <button
                  onClick={() => {
                    if (chat.trim()) {
                      setMessages((v) => [...v, chat.trim()]);
                      setChat("");
                    }
                  }}
                  className="grid h-9 w-9 place-items-center rounded-full bg-[#f3c653] text-black"
                >
                  <Send size={16} />
                </button>
              </div>
            </div>
          </div>
        </section>
        <aside className="hidden border-l border-white/8 bg-[#090c09] lg:block">
          <div className="sticky top-0 flex h-screen flex-col p-4">
            <div className="flex-1 overflow-y-auto">
              <div className="mb-4 text-lg font-semibold">Live chat</div>
              <div className="space-y-2">
                {[
                  "This is beautiful! 😍",
                  "Is this pure silk?",
                  "Can you show the pallu up close?",
                  "Do you have this in green?",
                  "How much is shipping?",
                ]
                  .concat(messages)
                  .map((m, i) => (
                    <div key={`${m}-${i}`} className="rounded-xl bg-white/[.03] px-3 py-2 text-sm">
                      <span className="font-semibold">{["Priya", "Amit", "Sneha", "Rohan", "Karan"][i % 5]} </span>
                      <span className="text-white/70">{m}</span>
                    </div>
                  ))}
              </div>
            </div>
            <div className="rounded-2xl border border-white/8 bg-black/30 p-3">
              <div className="mb-3 flex gap-3">
                <img src={product.images[0]} alt="" className="h-16 w-16 rounded-xl object-cover" />
                <div className="min-w-0">
                  <div className="text-xs text-[#f3c653]">{product.code}</div>
                  <div className="truncate text-sm font-semibold">{product.name}</div>
                  <div className="font-bold">₹{product.price.toLocaleString("en-IN")}</div>
                </div>
              </div>
              <button onClick={() => addToCart(product.id)} className="ld-gold-button w-full">
                Add to Bag
              </button>
            </div>
          </div>
        </aside>
      </div>
      <MobileBottomNav active="live" />
    </main>
  );
}

