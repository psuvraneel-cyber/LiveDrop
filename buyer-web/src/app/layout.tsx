import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  themeColor: "#0C0C0E",
};

const rawBaseUrl = (process.env.NEXT_PUBLIC_APP_BASE_URL || 'https://livedrop.in').replace(/^\uFEFF/, '').trim();
let siteBaseUrl: URL;
try {
  siteBaseUrl = new URL(rawBaseUrl);
} catch {
  siteBaseUrl = new URL('https://livedrop.in');
}

export const metadata: Metadata = {
  metadataBase: siteBaseUrl,
  title: {
    default: "LiveDrop.in — Boutique Fashion. Live Stories. Real People.",
    template: "%s | LiveDrop.in",
  },
  description: "Browse live boutique drops, discover exclusive artisan sarees and kurtis, and reserve single-piece fashion in real time.",
  openGraph: {
    siteName: "LiveDrop.in",
    type: "website",
    locale: "en_IN",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;0,700;1,400;1,600&family=Playfair+Display:ital,wght@0,600;0,700;1,500&family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
