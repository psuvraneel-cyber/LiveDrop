"use client";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { heroSlides } from "@/lib/data";
import { ChevronLeft, ChevronRight, Play } from "lucide-react";

export function Hero(){
 const [active,setActive]=useState(0);
 useEffect(()=>{const t=setInterval(()=>setActive(v=>(v+1)%heroSlides.length),7000);return()=>clearInterval(t)},[]);
 const slide=heroSlides[active];
 return <section className="relative overflow-hidden rounded-3xl border border-white/10 bg-black shadow-[0_24px_80px_rgba(0,0,0,.35)]">
   <div className="relative aspect-[16/10] min-h-[320px] lg:aspect-[16/6.5]"><AnimatePresence mode="wait"><motion.img key={slide.image} src={slide.image} alt="" className="absolute inset-0 h-full w-full object-cover" initial={{opacity:0,scale:1.04}} animate={{opacity:1,scale:1}} exit={{opacity:0}} transition={{duration:.65}}/><motion.div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(4,5,4,.92)_0%,rgba(4,5,4,.72)_34%,rgba(4,5,4,.1)_72%,rgba(4,5,4,.2))]" /></AnimatePresence>
   <div className="absolute inset-x-0 bottom-0 top-0 flex items-end p-5 lg:p-10"><div className="max-w-xl"><div className="mb-3 inline-flex rounded-full bg-[#ff375f] px-3 py-1 text-[10px] font-bold">● LIVE NOW</div><h1 className="ld-serif text-4xl leading-[.98] sm:text-5xl lg:text-6xl">{slide.title}</h1><p className="mt-3 max-w-lg text-sm text-white/70 lg:text-base">{slide.subtitle}</p><div className="mt-5 flex flex-wrap gap-3"><Link href="/live" className="ld-gold-button">Explore Live Drops →</Link><Link href="/live" className="ld-outline-button"><Play size={15}/> Watch Live</Link></div></div></div>
   <div className="absolute right-4 top-1/2 hidden -translate-y-1/2 flex-col gap-2 sm:flex"><button onClick={()=>setActive((active-1+heroSlides.length)%heroSlides.length)} aria-label="Previous slide" className="grid h-9 w-9 place-items-center rounded-full border border-white/10 bg-black/35"><ChevronLeft size={18}/></button><div className="rounded-full border border-white/10 bg-black/35 px-2 py-3 text-center text-[9px]">0{active+1}<div className="text-white/40">/0{heroSlides.length}</div></div><button onClick={()=>setActive((active+1)%heroSlides.length)} aria-label="Next slide" className="grid h-9 w-9 place-items-center rounded-full border border-white/10 bg-black/35"><ChevronRight size={18}/></button></div>
   <div className="absolute bottom-4 right-4 flex gap-1.5 sm:hidden">{heroSlides.map((_,i)=><button key={i} aria-label={`Go to slide ${i+1}`} onClick={()=>setActive(i)} className={`h-2 rounded-full transition-all ${i===active?"w-6 bg-[#f3c653]":"w-2 bg-white/30"}`}/>)}</div>
   </div>
 </section>
}
