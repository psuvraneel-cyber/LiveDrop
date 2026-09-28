export type Availability = "in-stock" | "low-stock" | "sold-out";

export interface Product {
  id: string;
  code: string;
  name: string;
  category: string;
  fabric: string;
  color: string;
  price: number;
  compareAt?: number;
  sizes: string[];
  rating: number;
  reviews: number;
  badge?: string;
  availability: Availability;
  images: string[];
  boutiqueId: string;
  description: string;
  features: string[];
}

export interface Boutique {
  id: string;
  name: string;
  tagline: string;
  location: string;
  live: boolean;
  viewers: string;
  image: string;
  avatar: string;
  whatsapp: string;
}

export interface CartItem {
  product: Product;
  quantity: number;
}
