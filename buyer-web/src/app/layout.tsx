<<<<<<< HEAD
import type { Metadata, Viewport } from "next";
import "./globals.css";
=======
import type { Metadata } from "next";
import type { ReactNode } from "react";
>>>>>>> 3b9f8cc6033a1b3db592f33a42f67a3cae5db77d

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  themeColor: "#16A34A",
};

<<<<<<< HEAD
export const metadata: Metadata = {
  title: "LiveDrop — Flash Sale Drops",
  description: "Browse live boutique drops and discover exclusive flash sales in real time.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
=======
export default function RootLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>) {
>>>>>>> 3b9f8cc6033a1b3db592f33a42f67a3cae5db77d
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
