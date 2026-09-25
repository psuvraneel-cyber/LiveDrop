import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { Cormorant_Garamond, Plus_Jakarta_Sans } from "next/font/google";
import { AppProviders } from "../components/providers/AppProviders";
import "./globals.css";

const cormorant = Cormorant_Garamond({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  style: ["normal", "italic"],
  variable: "--font-display",
  display: "swap",
});

const plusJakarta = Plus_Jakarta_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-sans",
  display: "swap",
});

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  themeColor: "#08080A",
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
    default: "LiveDrop — Haute Couture Indian Boutiques Streaming Live",
    template: "%s | LiveDrop",
  },
  description: "Discover verified Indian designer boutiques, explore handcrafted sarees and artisanal collections, and experience single-piece live stream drops.",
  openGraph: {
    siteName: "LiveDrop",
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
    <html lang="en" className={`${cormorant.variable} ${plusJakarta.variable}`}>
      <body className="ld-body-root">
        <AppProviders>{children}</AppProviders>
      </body>
    </html>
  );
}
