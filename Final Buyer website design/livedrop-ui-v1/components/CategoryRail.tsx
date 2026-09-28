"use client";
import { motion } from "motion/react";
import Image from "next/image";
import { categories } from "@/lib/data";

export function CategoryRail(){return <motion.div className="ld-scrollbar-none flex cursor-grab gap-3 overflow-x-auto pb-2 active:cursor-grabbing" drag="x" dragConstraints={{left:-460,right:0}} dragElastic={0.14}>{categories.map((c,i)=><motion.div key={c.name} whileTap={{scale:.95}} className="shrink-0 text-center"><div className={`mx-auto mb-1 h-14 w-14 rounded-full border ${i===0?"border-[#f3c653] shadow-[0_0_0_5px_rgba(243,198,83,.08)]":"border-white/10"} bg-white/5 p-1`}><Image src={c.image} alt="" width={52} height={52} className="h-full w-full rounded-full object-cover"/></div><div className={`text-[11px] ${i===0?"text-[#f3c653]":"text-white/65"}`}>{c.name}</div></motion.div>)}</motion.div>}
