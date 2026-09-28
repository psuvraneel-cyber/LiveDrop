"use client";
import Link from "next/link";
import { motion } from "motion/react";
import { Heart, ShoppingBag, Star } from "lucide-react";
import { useBuyer } from "@/components/BuyerProvider";
import type { Product } from "@/lib/types";

export function ProductCard({product}:{product:Product}){
 const { addToCart } = useBuyer();
 return <motion.article layout whileHover={{y:-6}} whileTap={{scale:.985}} transition={{type:"spring",stiffness:280,damping:23}} className="overflow-hidden rounded-2xl border border-white/8 bg-[#0f120f] shadow-[0_18px_40px_rgba(0,0,0,.24)]">
   <div className="relative aspect-[4/5] overflow-hidden bg-black">
     <Link href={`/product/${product.id}`} className="block h-full"><img src={product.images[0]} alt={product.name} className="h-full w-full object-cover transition duration-700 hover:scale-[1.045]" loading="lazy"/></Link>
     <div className="absolute left-3 top-3 rounded-full bg-black/70 px-2.5 py-1 text-[10px] font-bold text-white backdrop-blur">{product.badge ?? product.code}</div>
     <motion.button whileTap={{scale:.8}} aria-label="Wishlist" className="absolute right-3 top-3 rounded-full border border-white/10 bg-black/45 p-2 backdrop-blur"><Heart size={16}/></motion.button>
   </div>
   <div className="p-3">
     <Link href={`/product/${product.id}`} className="line-clamp-2 text-[14px] font-semibold leading-snug text-white lg:text-[16px]">{product.name}</Link>
     <div className="mt-1 flex items-center gap-1 text-[11px] text-white/55"><Star size={12} className="fill-[#f3c653] text-[#f3c653]"/>{product.rating} ({product.reviews})</div>
     <div className="mt-2 flex items-end justify-between gap-2"><div><div className="text-lg font-black text-white">₹{product.price.toLocaleString("en-IN")}</div>{product.compareAt && <div className="text-[11px] text-white/35 line-through">₹{product.compareAt.toLocaleString("en-IN")}</div>}</div><motion.button whileTap={{scale:.85}} onClick={()=>addToCart(product.id)} className="grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br from-[#ffe18f] to-[#d89d20] text-black shadow-[0_10px_30px_rgba(243,198,83,.18)]" aria-label={`Add ${product.name} to bag`}><ShoppingBag size={18}/></motion.button></div>
     <div className={`mt-2 inline-flex items-center gap-1 rounded-full border px-2 py-1 text-[10px] ${product.availability==='in-stock'?"border-emerald-500/30 bg-emerald-500/8 text-emerald-300":product.availability==='low-stock'?"border-amber-500/30 bg-amber-500/8 text-amber-300":"border-white/10 bg-white/5 text-white/40"}`}><span className="h-1.5 w-1.5 rounded-full bg-current"/>{product.availability==='in-stock'?"In Stock":product.availability==='low-stock'?"Low Stock":"Sold Out"}</div>
   </div>
 </motion.article>
}
