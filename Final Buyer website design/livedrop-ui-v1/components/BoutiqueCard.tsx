"use client";
import Link from "next/link";
import { motion } from "motion/react";
import { Check, MessageCircle } from "lucide-react";
import type { Boutique } from "@/lib/types";

export function BoutiqueCard({boutique}:{boutique:Boutique}){return <motion.article whileHover={{y:-4}} className="relative overflow-hidden rounded-2xl border border-white/8 bg-[#0d100d]">
<div className="absolute inset-0"><img src={boutique.image} alt="" className="h-full w-full object-cover opacity-45"/><div className="absolute inset-0 bg-gradient-to-t from-[#050605] via-[#070807]/50 to-transparent"/></div>
<div className="relative p-4"><div className="flex items-center justify-between"><div className="flex items-center gap-3"><img src={boutique.avatar} alt="" className="h-11 w-11 rounded-full border border-[#f3c653]/45 bg-black object-cover"/><div><div className="flex items-center gap-1 font-semibold">{boutique.name}<Check size={14} className="text-[#f3c653]"/></div><div className="text-[11px] text-white/55">{boutique.tagline}</div></div></div>{boutique.live&&<div className="rounded-full bg-[#ff375f] px-2.5 py-1 text-[10px] font-bold">LIVE · {boutique.viewers}</div>}</div><div className="mt-5 flex items-center gap-2"><Link href={`/shop#${boutique.id}`} className="ld-gold-button min-h-10 px-4 text-xs">Visit Boutique →</Link><a href={`https://wa.me/${boutique.whatsapp}`} aria-label="WhatsApp" className="grid h-10 w-10 place-items-center rounded-full border border-emerald-400/50 bg-black/60 text-emerald-300"><MessageCircle size={18}/></a></div></div></motion.article>}
