import type { Metadata } from "next";
import "./globals.css";
import { BuyerProvider } from "@/components/BuyerProvider";

export const metadata: Metadata = {
  title: "LiveDrop — Indian Luxury Live",
  description: "Luxury live-commerce storefront for independent Indian boutiques.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body><BuyerProvider>{children}</BuyerProvider></body>
    </html>
  );
}
