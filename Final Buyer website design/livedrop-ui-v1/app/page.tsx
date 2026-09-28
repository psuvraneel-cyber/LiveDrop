import { SiteHeader } from "@/components/SiteHeader";
import { MobileBottomNav } from "@/components/MobileBottomNav";
import { Hero } from "@/components/Hero";
import { CategoryRail } from "@/components/CategoryRail";
import { ProductCard } from "@/components/ProductCard";
import { BoutiqueCard } from "@/components/BoutiqueCard";
import { TrustStrip } from "@/components/TrustStrip";
import { Footer } from "@/components/Footer";
import { SectionTitle } from "@/components/SectionTitle";
import { boutiques, products } from "@/lib/data";

export default function HomePage(){return <><SiteHeader/><main className="ld-shell ld-bottom-safe"><div className="ld-section"><Hero/></div><section><CategoryRail/></section><section className="ld-section"><SectionTitle title="Featured Pieces" subtitle="Handpicked from independent boutiques"/><div className="ld-grid-products">{products.slice(0,4).map(p=><ProductCard key={p.id} product={p}/>)}</div></section><section id="boutiques" className="ld-section"><SectionTitle title="Live Boutiques" subtitle="Shop directly from independent artisans"/><div className="grid gap-3 lg:grid-cols-3">{boutiques.map(b=><BoutiqueCard key={b.id} boutique={b}/>)}</div></section><section className="ld-section"><TrustStrip/></section><section className="ld-card overflow-hidden p-5 lg:p-7"><div className="grid gap-5 lg:grid-cols-[1fr_auto] lg:items-center"><div><div className="ld-serif text-2xl lg:text-3xl">Stay updated with new drops</div><p className="mt-1 text-sm text-white/55">Be the first to know about live sessions, new collections and exclusive pieces.</p></div><div className="flex gap-2"><input className="min-h-11 min-w-0 flex-1 rounded-full border border-white/10 bg-black/30 px-4 text-sm outline-none placeholder:text-white/30" placeholder="Enter your email address"/><button className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-[#f3c653] font-black text-black">→</button></div></div></section><Footer/></main><MobileBottomNav/></>}
