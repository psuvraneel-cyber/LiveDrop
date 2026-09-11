import React from 'react';
import { PublicProductView } from '../types/domain';
import { ProductCard } from './ProductCard';

export interface ProductGridProps {
  products: PublicProductView[];
}

export function ProductGrid({ products }: ProductGridProps) {
  return (
    <div className="ld-product-grid" data-testid="product-grid" role="region" aria-label="Drop product catalog">
      {products.map((product) => (
        <ProductCard key={product.id} product={product} />
      ))}
    </div>
  );
}
