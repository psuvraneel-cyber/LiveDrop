import type { Metadata } from 'next';
import { SellerPasswordResetView } from '../../../components/auth/SellerPasswordResetView';

// Account-recovery page: never indexed, never cached, and the one-time link is never sent
// onwards as a Referer.
export const metadata: Metadata = {
  title: 'Reset seller password',
  robots: {
    index: false,
    follow: false,
    nocache: true,
    googleBot: { index: false, follow: false },
  },
  referrer: 'no-referrer',
};

export default function SellerResetPasswordPage() {
  return <SellerPasswordResetView />;
}
