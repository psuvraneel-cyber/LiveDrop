import type { Boutique, Product } from "@/lib/types";

const img = (name: string) => `/images/products/${name}.svg`;
const bout = (name: string) => `/images/boutiques/${name}.svg`;

export const categories = [
  { name: "All", image: img("all") },
  { name: "Sarees", image: img("sarees") },
  { name: "Kurtis", image: img("kurtis") },
  { name: "Lehengas", image: img("lehengas") },
  { name: "Dupattas", image: img("dupattas") },
  { name: "Jewellery", image: img("jewellery") },
  { name: "Menswear", image: img("menswear") },
  { name: "Home & Living", image: img("home") },
  { name: "Gift Sets", image: img("gifts") },
];

export const boutiques: Boutique[] = [
  { id: "sonali", name: "Sonali's Boutique", tagline: "Heritage Silks & Handlooms", location: "Kolkata", live: true, viewers: "1.2K", image: bout("sonali"), avatar: bout("sonali-avatar"), whatsapp: "918700000001" },
  { id: "suv", name: "Suv's", tagline: "Contemporary Ethnic Wear", location: "Kolkata", live: true, viewers: "856", image: bout("suv"), avatar: bout("suv-avatar"), whatsapp: "918700000002" },
  { id: "suvraneel", name: "Suvraneel Boutique", tagline: "Timeless Indian Fashion", location: "Kolkata", live: false, viewers: "—", image: bout("suvraneel"), avatar: bout("suvraneel-avatar"), whatsapp: "918700000003" },
];

export const products: Product[] = [
  {
    id: "a01", code: "#A01", name: "Banarasi Katan Silk Saree", category: "Sarees", fabric: "Silk", color: "Red", price: 2450, compareAt: 3200,
    sizes: ["S", "M", "L", "XL"], rating: 4.8, reviews: 320, badge: "Bestseller", availability: "in-stock",
    images: [img("p01"), img("p01-alt"), img("p01-close")], boutiqueId: "sonali",
    description: "A luminous Katan silk saree with hand-finished zari and a rich festive drape, designed for intimate celebrations and statement evenings.",
    features: ["Pure silk", "Handwoven", "Single piece", "Festive wear"],
  },
  {
    id: "a02", code: "#A02", name: "Chanderi Cotton Saree", category: "Sarees", fabric: "Cotton", color: "Mint Green", price: 1650,
    sizes: ["M", "L", "XL"], rating: 4.6, reviews: 184, badge: "Trending", availability: "in-stock",
    images: [img("p02"), img("p02-alt")], boutiqueId: "suv",
    description: "Breathable Chanderi cotton with subtle sheen and a feather-light fall for day-to-evening styling.",
    features: ["Chanderi cotton", "Lightweight", "Easy drape", "Everyday luxury"],
  },
  {
    id: "a03", code: "#A03", name: "Handloom Tussar Silk Saree", category: "Sarees", fabric: "Tussar", color: "Pink", price: 3100, compareAt: 3850,
    sizes: ["S", "M", "L"], rating: 4.7, reviews: 210, badge: "New Arrival", availability: "low-stock",
    images: [img("p03"), img("p03-alt"), img("p03-close")], boutiqueId: "sonali",
    description: "A handloom Tussar silk saree with an elegant body, handcrafted border and a soft festive palette.",
    features: ["Tussar silk", "Handloom", "Limited stock", "Occasion wear"],
  },
  {
    id: "a04", code: "#A04", name: "Zari Embroidered Georgette Saree", category: "Sarees", fabric: "Georgette", color: "Ivory", price: 850,
    sizes: ["Free Size"], rating: 4.5, reviews: 98, badge: "20% OFF", availability: "in-stock",
    images: [img("p04"), img("p04-alt")], boutiqueId: "suvraneel",
    description: "Soft georgette with delicate zari embroidery, designed to photograph beautifully while staying easy to style.",
    features: ["Georgette", "Zari work", "Soft fall", "Festive"],
  },
  {
    id: "a05", code: "#A05", name: "Kanchipuram Pure Silk Saree", category: "Sarees", fabric: "Silk", color: "Gold", price: 4850,
    sizes: ["M", "L", "XL"], rating: 4.9, reviews: 420, badge: "Premium", availability: "in-stock",
    images: [img("p05")], boutiqueId: "sonali",
    description: "Classic Kanchipuram silk with a substantial handloom body and heirloom-ready zari border.",
    features: ["Kanchipuram", "Pure silk", "Handloom", "Heirloom"],
  },
  {
    id: "a06", code: "#A06", name: "Organza Embroidered Saree", category: "Sarees", fabric: "Organza", color: "Blue", price: 2950,
    sizes: ["S", "M", "L"], rating: 4.6, reviews: 156, badge: "Handpicked", availability: "in-stock",
    images: [img("p06")], boutiqueId: "suv",
    description: "Structured organza with embroidery detailing and a crisp contemporary silhouette.",
    features: ["Organza", "Embroidered", "Crisp drape", "Day to night"],
  },
];

export const heroSlides = [
  { title: "Tradition Meets Timeless Beauty", subtitle: "Live shopping · Authentic · From Indian artisans", image: img("hero-1") },
  { title: "The Evening Edit", subtitle: "Handpicked festive pieces from independent boutiques", image: img("hero-2") },
  { title: "One-of-a-Kind. Live.", subtitle: "Discover limited pieces before they are gone", image: img("hero-3") },
];
