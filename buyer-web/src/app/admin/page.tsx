import type { Metadata } from 'next';
import { AdminConsoleView } from '../../components/admin/AdminConsoleView';

// Operator console: never indexed or cached, and never sends a Referer.
export const metadata: Metadata = {
  title: 'LiveDrop admin',
  robots: {
    index: false,
    follow: false,
    nocache: true,
    googleBot: { index: false, follow: false },
  },
  referrer: 'no-referrer',
};

export default function AdminPage() {
  return <AdminConsoleView />;
}
