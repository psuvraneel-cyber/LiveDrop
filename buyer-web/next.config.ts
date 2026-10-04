import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  turbopack: {
    root: __dirname,
  },
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "**.supabase.co",
      },
      {
        protocol: "https",
        hostname: "**.cloudflare.com",
      },
      {
        protocol: "https",
        hostname: "images.unsplash.com",
      },
    ],
  },
  async headers() {
    return [
      {
        source: "/drop/:slug*",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=0, s-maxage=5, stale-while-revalidate=59",
          },
          {
            key: "CDN-Cache-Control",
            value: "public, s-maxage=10, stale-while-revalidate=59",
          },
          {
            key: "Surrogate-Control",
            value: "public, max-age=10, stale-while-revalidate=59",
          },
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          {
            key: "X-Frame-Options",
            value: "SAMEORIGIN",
          },
          {
            key: "Referrer-Policy",
            value: "strict-origin-when-cross-origin",
          },
        ],
      },
      {
        source: "/(.*)",
        headers: [
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          {
            key: "Referrer-Policy",
            value: "strict-origin-when-cross-origin",
          },
        ],
      },
      {
        // Seller account recovery (/seller/reset-password): the URL carries a one-time token.
        // Listed last so these values win over the catch-all above.
        source: "/seller/:path*",
        headers: [
          {
            key: "X-Robots-Tag",
            value: "noindex, nofollow, noarchive",
          },
          {
            key: "Referrer-Policy",
            value: "no-referrer",
          },
          {
            key: "Cache-Control",
            value: "no-store, max-age=0",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
